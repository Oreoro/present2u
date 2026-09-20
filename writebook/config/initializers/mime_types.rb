# Propshaft looks up asset content types through Rails' Mime registry. The
# KaTeX ES modules are shipped as .mjs, which Rails doesn't know by default, so
# they were served with an empty Content-Type and the browser refused to load
# them as modules. Register the type so importmap can serve them.
Mime::Type.register "text/javascript", :mjs unless Mime::Type.lookup_by_extension(:mjs)
