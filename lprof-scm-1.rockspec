package = "lprof"
version = "scm-1"
source = {
   url = "git://github.com/joelself/LProf.lua",
   dir = "LProf.lua"
}
description = {
   summary  = "A simple lua profiler that works with LuaJIT and prints a gorgeous report file in columns.",
   homepage = "https://github.com/joelself/LProf.lua",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      LProf = "LProf.lua"
   }
}
