// Generates an iOS Shortcuts-importable plist with one tokenized ping URL.
// The imported shortcut performs a GET request and does not require login.

const SHORTCUT_NAME = 'Keep Contact Ping'

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function buildPlist(pingUrl: string): string {
  const url = xmlEscape(pingUrl)
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>WFWorkflowMinimumClientVersion</key>
\t<integer>900</integer>
\t<key>WFWorkflowMinimumClientVersionString</key>
\t<string>900</string>
\t<key>WFWorkflowClientVersion</key>
\t<string>2607.0.5</string>
\t<key>WFWorkflowIcon</key>
\t<dict>
\t\t<key>WFWorkflowIconStartColor</key>
\t\t<integer>946986751</integer>
\t\t<key>WFWorkflowIconGlyphNumber</key>
\t\t<integer>59511</integer>
\t</dict>
\t<key>WFWorkflowImportQuestions</key>
\t<array/>
\t<key>WFWorkflowTypes</key>
\t<array>
\t\t<string>NCWidget</string>
\t\t<string>WatchKit</string>
\t</array>
\t<key>WFWorkflowInputContentItemClasses</key>
\t<array>
\t\t<string>WFAppStoreAppContentItem</string>
\t\t<string>WFArticleContentItem</string>
\t\t<string>WFContactContentItem</string>
\t\t<string>WFDateContentItem</string>
\t\t<string>WFEmailAddressContentItem</string>
\t\t<string>WFGenericFileContentItem</string>
\t\t<string>WFImageContentItem</string>
\t\t<string>WFiTunesProductContentItem</string>
\t\t<string>WFLocationContentItem</string>
\t\t<string>WFDCMapsLinkContentItem</string>
\t\t<string>WFAVAssetContentItem</string>
\t\t<string>WFPDFContentItem</string>
\t\t<string>WFPhoneNumberContentItem</string>
\t\t<string>WFRichTextContentItem</string>
\t\t<string>WFSafariWebPageContentItem</string>
\t\t<string>WFStringContentItem</string>
\t\t<string>WFURLContentItem</string>
\t</array>
\t<key>WFWorkflowActions</key>
\t<array>
\t\t<dict>
\t\t\t<key>WFWorkflowActionIdentifier</key>
\t\t\t<string>is.workflow.actions.downloadurl</string>
\t\t\t<key>WFWorkflowActionParameters</key>
\t\t\t<dict>
\t\t\t\t<key>WFURL</key>
\t\t\t\t<string>${url}</string>
\t\t\t\t<key>WFHTTPMethod</key>
\t\t\t\t<string>GET</string>
\t\t\t\t<key>ShowHeaders</key>
\t\t\t\t<false/>
\t\t\t</dict>
\t\t</dict>
\t</array>
</dict>
</plist>`
}

Deno.serve((req) => {
  const url = new URL(req.url)
  const token = url.searchParams.get('token')
  if (!token) {
    return new Response('missing token', { status: 400 })
  }
  const base = Deno.env.get('SUPABASE_URL')!
  const pingUrl = `${base}/functions/v1/ping?token=${token}`
  const plist = buildPlist(pingUrl)

  return new Response(plist, {
    headers: {
      'Content-Type': 'application/x-plist',
      'Content-Disposition': `attachment; filename="${SHORTCUT_NAME}.plist"`,
      'Access-Control-Allow-Origin': '*',
    },
  })
})
