#!/usr/local/bin/lua
pcall('require','luarocks.require')
require'lfs'

local args = {...}

local provider = args[3] or 'tvsubtitles'

local getfile = require('provider.' .. provider)

local directory = args[1] or  '.'  

local files = {}
local subs = {}

local loglevel = args[5] or 2

local language = args[2] or 'en'

function log(l, ...)
	if l <= loglevel then
		print(...)
	end
end

function normalize(name)
	name = string.gsub(string.lower(name),"[.:_\-'!]","")
	name = string.gsub(name, "%w+", function(n)
		return tonumber(n) or string.len(n)>2 and n or ''
	end)
	return string.gsub(name, " ","")
end

function store(repository, key, value)
	local pos = #repository+1
	value.key = key
	repository.index = repository.index or {}
	table.insert(repository, pos, value)
	repository.index[key] =repository.index[key] or {}
	table.insert(repository.index[key], pos)
	return pos
end

function add(fileName, series, season, episode, release, ext)
	if ext=='avi' or ext=='mpg' then
	      return store(files,  tostring(series) .. '.'..tostring(season)..'x'..tostring(episode), {fileName=fileName, series=series, season=season, episode=episode, release=release, ext=ext})
	elseif ext=='srt' or ext=='txt' then
	      return store(subs,  tostring(series) .. '.'..tostring(season)..'x'..tostring(episode), {fileName=fileName, series=series, season=season, episode=episode, release=release, ext=ext})
	end
end

function filter(filters, series, season, episode)
	return string.find(string.lower(series or ''), string.lower(filters.series  or ''))
			and  tonumber(season)==tonumber(filters.season) or tonumber(season)
			and  tonumber(episode)==tonumber(filters.episode) or tonumber(episode)
end

standards = {
	['([^/]*)S(%d%d)E(%d%d)(.*)[.]([samt][vrpx][itg])'] = function(fileName, filters, series, season, episode, release, ext)   
		if filter(filters, series, season, episode) then
				return add( fileName, normalize(series), tonumber(season), tonumber(episode), release, string.lower(ext))
		end
	end,
	['([^/]*)%s*-*%s*(%d+)x(%d+)%s*-*%s*(.*)[.]([asmt][rxvp][itg])'] = function(fileName, filters, series, season, episode, release, ext)   
		if filter(filters, series, season, episode) then
				return add( fileName, string.gsub(series,"[ ,.:_\-]",""), tonumber(season), tonumber(episode), release, string.lower(ext))
		end
	end,
	['([^/]*)%s*-*%s*(%d)(%d%d)%s*-*%s*(.*)[.]([asmt][xrvp][itg])'] = function(fileName, filters, series, season, episode, release, ext)   
		if filter(filters, series, season, episode) then
				return add( fileName, string.gsub(series,"[ ,.:_\-]",""), tonumber(season), tonumber(episode), release, string.lower(ext))
		end
	end,
	['([^/]*)%s*-*%s*[\[](%d+)x(%d+)[\]]%s*-*%s*(.*)[.]([atsm][rxvp][itg])'] = function(fileName, filters, series, season, episode, release, ext)   
		if filter(filters, series, season, episode) then
				return add( fileName, string.gsub(series,"[ ,.:_\-]",""), tonumber(season), tonumber(episode), release, string.lower(ext))
		end
	end,
	['([^/]*)[\[](%d+)x(%d+)[\]](.*)[.]([atsm][rxvp][itg])'] = function(fileName, filters, series, season, episode, release, ext)   
		if filter(filters, series, season, episode) then
				return add( fileName, string.gsub(series,"[ ,.:_\-]",""), tonumber(season), tonumber(episode), release, string.lower(ext))
		end
	end,
	
}

function processFile(fileName, series, season, episode)
	log(2,'> file:', fileName)
	for p, f in pairs(standards) do
		local fileName, res, m = string.gsub(fileName, p, function(...) return f(fileName, {series, season, episode}, ...) end)
		if res>0 then
			return niil
		end
	end
	return fileName
end

function process(directory, language, ...)
log(1,'processing:', directory, ...)
	local f = lfs.dir(directory)

	local fileName = f()
	while fileName do
		if fileName ~= '.' and fileName ~= '..'  then
		fileName =   directory .. '/'..fileName
			local isdir = lfs.attributes(fileName, 'mode') == 'directory'
			if isdir then
				process(fileName)
			else
				fileName = processFile(fileName, ...)
				if fileName then
					log(2,"Ignored:", fileName)
				end
			end
		end
		fileName = f()
	end
end

function subFileName(file, language)
	language = language or 'en'
	local fileName = (string.gsub(file.fileName, "(.*)[.]([am][vp][gi])", "%1." .. language .. ".srt"))
	fileName = (string.gsub(fileName, [[//]], [[/]]))
	return (string.gsub(fileName, [[\\]], [[\]]))
end

function loadsubtitle(sub)
	local ff = io.open(sub.fileName, 'r')
	sub.text = ff:read'*a'
	ff:close()
	return sub.text, sub.fileName
end


process(directory, language, args[3], args[4], args[5])

local written = 0
local downloaded = 0

table.foreachi(files, function(_,file)
	log(2,file.series, file.season, file.episode)
	
	local allsubs = subs.index and subs.index[file.key] 
	
	if allsubs and #allsubs > 0 then 
	
		for _,keys in pairs(allsubs) do
			local sub = subs[tonumber(keys)]
			local _,_,language = string.find(sub.release or '', "[.]([a-z][a-z])$")
			language = language or 'en'

			getfile.addsub(file, sub.fileName, sub.release, language, true)
			loadsubtitle(sub)
		end
	
	else
		local ok,msg = getfile.loadsubtitles({file}, language)
		if ok then
			downloaded = downloaded + 1
		else
			print('>error:', msg)
		end
	end
	
	if not file.bestsub or not  file.bestsub.sub or not file.bestsub.sub.text then
		getfile.choosebestsub(file, file, language)
	end
	
	if file.bestsub then
		local newFileName = subFileName(file, language)
		local s = io.open(newFileName, 'r')
		if not s then
			log(2, 'Creating:', newFileName)
			local d = io.open(newFileName, 'w')
			assert(d, 'could not open the file for writing')
			assert(file.bestsub.sub.text, 'could not find the text for the sub')
			d:write(file.bestsub.sub.text)
			log(3, 'written', string.len(file.bestsub.sub.text), 'bytes')
			d:close()
			
			written = written + 1

		else
			s:close()
			log(2,'file', newFileName, ' exists')
		end
	else
		print('no best subtitle for the file:', file.fileName)
	end
	
end)

print("Saved ", written, " subtitles")
print(downloaded, " were downloaded")
