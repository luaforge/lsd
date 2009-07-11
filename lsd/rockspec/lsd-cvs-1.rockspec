package = "lsd"
version = "cvs-1"
source = {
   url = "cvs://:pserver:anonymous@cvs.luaforge.net:/cvsroot/lsd",
   cvs_tag = "HEAD",
}
description = {
   summary = "LSD",
   detailed = [[Lua Subtitle Downloader is a program that scans all movie files from a directory and its subdirectories and downloads their respective subtitles from different websites.]],
   license = "MIT/X11",
   homepage = "http://lsd.luaforge.net/"
}
dependencies = {
   "lua >= 5.1",
   "luafilesystem cvs",
   "luasocket >= 2.0"
}
build = {
   type = "none",
   install = { 
   		lua = { 			
   			["provider.tvsubtitles"] = [[src/provider/tvsubtitles.lua]],
   			["provider.abydosgate"] = [[src/provider/abydosgate.lua]],
   		},
   		bin = { "src/lsd" }
   	}
}