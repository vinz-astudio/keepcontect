use tauri::{
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};

fn elapsed_tick_ms(current: u32, last_input: u32) -> u64 {
    current.wrapping_sub(last_input) as u64
}

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

    pub fn get_idle_time_ms() -> Option<u64> {
        let mut lii = LastInputInfo {
            cb_size: mem::size_of::<LastInputInfo>() as u32,
            dw_time: 0,
        };
        unsafe {
            if GetLastInputInfo(&mut lii) != 0 {
                let current_tick = GetTickCount();
                Some(super::elapsed_tick_ms(current_tick, lii.dw_time))
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

    pub fn get_idle_time_ms() -> Option<u64> {
        unsafe {
            let seconds = CGEventSourceSecondsSinceLastEventType(0, 0xFFFFFFFF);
            if seconds >= 0.0 {
                Some((seconds * 1000.0) as u64)
            } else {
                None
            }
        }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod sys_idle {
    pub fn get_idle_time_ms() -> Option<u64> {
        None
    }
}

#[tauri::command]
fn get_system_idle_time_ms() -> Option<u64> {
    sys_idle::get_idle_time_ms()
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TauriInputEvidenceSample {
    collector_contract: &'static str,
    channel: &'static str,
    probe_available: bool,
    sample_time_ms: u64,
    idle_duration_ms: u64,
    last_input_at_ms: u64,
}

fn reconstruct_input_sample(
    sample_time_ms: u64,
    idle_duration_ms: Option<u64>,
) -> Option<TauriInputEvidenceSample> {
    let idle_duration_ms = idle_duration_ms?;
    let last_input_at_ms = sample_time_ms.checked_sub(idle_duration_ms)?;
    Some(TauriInputEvidenceSample {
        collector_contract: "tauri-passive-evidence-v1",
        channel: "tauri",
        probe_available: true,
        sample_time_ms,
        idle_duration_ms,
        last_input_at_ms,
    })
}

#[tauri::command]
fn get_tauri_input_evidence_sample() -> Option<TauriInputEvidenceSample> {
    let sample_time_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_millis()
        .try_into()
        .ok()?;
    reconstruct_input_sample(sample_time_ms, sys_idle::get_idle_time_ms())
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TauriCoverageCapability {
    collector_contract: &'static str,
    collector_state: &'static str,
    idle_probe_available: bool,
    app_version: String,
    channel: &'static str,
}

fn build_shadow_coverage_capability(
    idle_probe_available: bool,
    app_version: &str,
) -> TauriCoverageCapability {
    TauriCoverageCapability {
        collector_contract: "tauri-idle-v1",
        collector_state: if idle_probe_available {
            "operational"
        } else {
            "unavailable"
        },
        idle_probe_available,
        app_version: app_version.to_string(),
        channel: "tauri",
    }
}

#[tauri::command]
fn get_alert_shadow_coverage_capability(
    app: tauri::AppHandle,
) -> TauriCoverageCapability {
    let version = app.package_info().version.to_string();
    build_shadow_coverage_capability(sys_idle::get_idle_time_ms().is_some(), &version)
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
    .invoke_handler(tauri::generate_handler![
      get_system_idle_time_ms,
      get_tauri_input_evidence_sample,
      get_alert_shadow_coverage_capability,
      download_and_install,
      open_in_browser
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

#[cfg(test)]
mod shadow_coverage_tests {
    use super::*;

    #[test]
    fn tauri_capability_is_unavailable_when_idle_probe_is_missing() {
        let value = build_shadow_coverage_capability(false, "0.5.20");
        assert_eq!(value.collector_state, "unavailable");
        assert!(!value.idle_probe_available);
    }

    #[test]
    fn tauri_capability_contract_is_fixed() {
        let value = build_shadow_coverage_capability(true, "0.5.20");
        assert_eq!(value.collector_contract, "tauri-idle-v1");
        assert_eq!(value.collector_state, "operational");
        assert_eq!(value.channel, "tauri");
        assert_eq!(value.app_version, "0.5.20");
    }
}

#[cfg(test)]
mod passive_input_evidence_tests {
    use super::*;

    #[test]
    fn reconstructs_last_input_from_the_same_sample_clock() {
        let sample = reconstruct_input_sample(1_800_000, Some(300_000)).unwrap();
        assert_eq!(sample.sample_time_ms, 1_800_000);
        assert_eq!(sample.idle_duration_ms, 300_000);
        assert_eq!(sample.last_input_at_ms, 1_500_000);
        assert_eq!(sample.channel, "tauri");
        assert_eq!(sample.collector_contract, "tauri-passive-evidence-v1");
    }

    #[test]
    fn tick_count_wrap_is_elapsed_time_not_future_input() {
        assert_eq!(elapsed_tick_ms(25, u32::MAX - 24), 50);
    }

    #[test]
    fn unavailable_probe_returns_no_sample() {
        assert!(reconstruct_input_sample(1_800_000, None).is_none());
    }

    #[test]
    fn clock_guard_rejects_an_idle_duration_before_unix_epoch() {
        assert!(reconstruct_input_sample(1_000, Some(1_001)).is_none());
    }
}
