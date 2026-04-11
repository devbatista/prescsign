WickedPdf.config ||= {}
WickedPdf.config.merge!(
  exe_path: ENV.fetch("WKHTMLTOPDF_PATH", "/usr/bin/wkhtmltopdf"),
  enable_local_file_access: true
)
