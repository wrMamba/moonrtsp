///|
/// Parse comma separated quoted authentication parameters without splitting quoted commas.
pub fn parse_parameters(text : String) -> Map[String,String] raise RtspError {
 require(text.length() <= 8192 && clean(text), "parameter length or characters")
 let result : Map[String,String] = Map([])
 let mut i = 0
 while i < text.length() {
  while i < text.length() && (text[i] == ' ' || text[i] == ',') { i += 1 }
  if i == text.length() { break }
  let start = i
  while i < text.length() && text[i] != '=' && text[i] != ',' { i += 1 }
  require(i < text.length() && text[i] == '=', "parameter equals")
  let key = lower(trim(text[start:i].to_owned()))
  require(key.length() > 0 && !result.contains(key), "duplicate or empty parameter")
  i += 1
  while i < text.length() && text[i] == ' ' { i += 1 }
  let value = StringBuilder()
  if i < text.length() && text[i] == '"' {
   i += 1
   let mut ended = false
   while i < text.length() {
    let c = text[i]
    i += 1
    if c == '"' { ended = true; break }
    if c == '\\' { require(i < text.length(), "quoted escape"); value.write_string(text[i:i+1].to_owned()); i += 1 }
    else { value.write_string(text[i-1:i].to_owned()) }
   }
   require(ended, "unterminated quoted parameter")
   while i < text.length() && text[i] == ' ' { i += 1 }
   require(i == text.length() || text[i] == ',', "quoted parameter separator")
  } else {
   let begin = i
   while i < text.length() && text[i] != ',' { i += 1 }
   value.write_string(trim(text[begin:i].to_owned()))
  }
  result[key] = value.to_string()
  require(result.length() <= 32, "parameter count")
 }
 result
}

///|
fn quoted(s : String) -> String {
 let out = StringBuilder()
 out.write_char('"')
 for c in s { if c == '"' || c == '\\' { out.write_char('\\') }; out.write_char(c) }
 out.write_char('"')
 out.to_string()
}
