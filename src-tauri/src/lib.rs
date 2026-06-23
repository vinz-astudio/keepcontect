use tauri::{
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};

#[cfg(target_os = "windows")]
mod sys_idle {
    use std::mem;

    #[repr(C)]
    struct LastInputInfo {
        cb_size: u32,
        dw_time: u32,
    }

    #[link(name = "user32")]
    extern "system" {
        fn GetLastInputInfo(plii: *mut LastInputInfo) -> i32;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GetTickCount() -> u32;
    }

    pub fn get_idle_time_ms() -> Option<u32> {
        let mut lii = LastInputInfo {
            cb_size: mem::size_of::<LastInputInfo>() as u32,
            dw_time: 0,
        };
        unsafe {
            if GetLastInputInfo(&mut lii) != 0 {
                let current_tick = GetTickCount();
                Some(current_tick.wrapping_sub(lii.dw_time))
            } else {
                None
            }
        }
    }
}

#[cfg(target_os = "macos")]
mod sys_idle {
    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGEventSourceSecondsSinceLastEventType(source_state: i32, event_type: u32) -> f64;
    }

    pub fn get_idle_time_ms() -> Option<u32> {
        unsafe {
            let seconds = CGEventSourceSecondsSinceLastEventType(0, 0xFFFFFFFF);
            if seconds >= 0.0 {
                Some((seconds * 1000.0) as u32)
            } else {
                None
            }
        }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod sys_idle {
    pub fn get_idle_time_ms() -> Option<u32> {
        None
    }
}

#[tauri::command]
fn get_system_idle_time_ms() -> Option<u32> {
    sys_idle::get_idle_time_ms()
}

#[tauri::command]
async fn download_and_install(window: tauri::Window, url: String) -> Result<(), String> {
  tauri::async_runtime::spawn_blocking(move || {
    use std::io::{Read, Write};
    let temp_dir = std::env::temp_dir();
    let installer_path = temp_dir.join("KeepContact-Setup.exe");

    let response = ureq::get(&url)
      .call()
      .map_err(|e| e.to_string())?;

    let total_size = response
      .header("Content-Length")
      .and_then(|v| v.parse::<u64>().ok())
      .unwrap_or(0);
      
    let mut reader = response.into_reader();
    let mut file = std::fs::File::create(&installer_path)
      .map_err(|e| e.to_string())?;

    let mut buffer = [0; 8192];
    let mut downloaded = 0;

    loop {
      let bytes_read = reader.read(&mut buffer).map_err(|e| e.to_string())?;
      if bytes_read == 0 {
        break;
      }
      file.write_all(&buffer[..bytes_read]).map_err(|e| e.to_string())?;
      downloaded += bytes_read as u64;

      if total_size > 0 {
        let percent = (downloaded as f64 / total_size as f64 * 100.0) as u32;
        let _ = window.emit("download-progress", percent);
      }
    }

    #[cfg(target_os = "windows")]
    {
      let current_exe = std::env::current_exe().map_err(|e| e.to_string())?;
      std::process::Command::new("powershell")
        .args(&[
          "-NoProfile",
          "-WindowStyle", "Hidden",
          "-Command",
          &format!(
            "Start-Sleep -Seconds 2; Start-Process '{}' -ArgumentList '/S'; Start-Sleep -Seconds 2; while (Get-Process -Name 'KeepContact-Setup' -ErrorAction SilentlyContinue) {{ Start-Sleep -Seconds 1 }}; Start-Process '{}'",
            installer_path.display(),
            current_exe.display()
          )
        ])
        .spawn()
        .map_err(|e| e.to_string())?;
    }

    #[cfg(not(target_os = "windows"))]
    {
      std::process::Command::new(installer_path)
        .spawn()
        .map_err(|e| e.to_string())?;
    }

    std::process::exit(0);
  }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
fn open_in_browser(url: String) -> Result<(), String> {
  #[cfg(target_os = "windows")]
  {
    std::process::Command::new("cmd")
      .args(&["/C", "start", "", &url])
      .spawn()
      .map_err(|e| e.to_string())?;
  }
  #[cfg(target_os = "macos")]
  {
    std::process::Command::new("open")
      .arg(&url)
      .spawn()
      .map_err(|e| e.to_string())?;
  }
  #[cfg(target_os = "linux")]
  {
    std::process::Command::new("xdg-open")
      .arg(&url)
      .spawn()
      .map_err(|e| e.to_string())?;
  }
  Ok(())
}


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
      if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
      }
    }))
    .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--silently"])))
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // Create Tray Menu and Tray Icon
      let show_i = MenuItem::with_id(app, "show", "Open Keep Contact", true, None::<&str>)?;
      let checkin_i = MenuItem::with_id(app, "checkin", "Check in now", true, None::<&str>)?;
      let quit_i = MenuItem::with_id(app, "quit", "Exit", true, None::<&str>)?;
      let menu = Menu::with_items(app, &[&show_i, &checkin_i, &quit_i])?;

      let icon = app.default_window_icon().cloned();
      let mut tray_builder = TrayIconBuilder::new()
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
          "quit" => {
            app.exit(0);
          }
          "show" => {
            if let Some(window) = app.get_webview_window("main") {
              let _ = window.show();
              let _ = window.set_focus();
            }
          }
          "checkin" => {
            if let Some(window) = app.get_webview_window("main") {
              let _ = window.show();
              let _ = window.set_focus();
              let _ = window.emit("tray-checkin", ());
            }
          }
          _ => {}
        })
        .on_tray_icon_event(|tray, event| {
          if let TrayIconEvent::Click { button: tauri::tray::MouseButton::Left, .. } = event {
            let app = tray.app_handle();
            if let Some(window) = app.get_webview_window("main") {
              let _ = window.show();
              let _ = window.set_focus();
            }
          }
        });

      if let Some(ic) = icon {
        tray_builder = tray_builder.icon(ic);
      }
      
      let _tray = tray_builder.build(app)?;

      Ok(())
    })
    .on_window_event(|window, event| {
      if let tauri::WindowEvent::CloseRequested { api, .. } = event {
        api.prevent_close();
        let _ = window.hide();
      }
    })
    .invoke_handler(tauri::generate_handler![get_system_idle_time_ms, download_and_install, open_in_browser])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
