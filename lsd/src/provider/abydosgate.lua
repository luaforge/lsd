pcall(require,'luarocks.require')

module('provider.abydosgate', package.seeall)

local http = require'socket.http'
local lfs = require'lfs'
local zip = require'zip'

local out = io.output();

local baseurl = "http://subtitles.stargate-sg1.hu/getsub.php?evad=A2x&nyelv=en&mod=lista"

local shows={}
local getaliases=loadfile'./aliases.conf' 
local aliases=getaliases and getaliases() 
aliases = aliases or {
	["American Dad"]="American Dad!",
	["DoctorWho [2005]"]="Doctor Who",
}

local cache={}
local cacheduration = 3600 * 3 -- 3 hours

function normalize(name)
	name = string.gsub(string.lower(name),"[.:_\-'!]","")
	name = string.gsub(name, "%w+", function(n)
		return tonumber(n) or string.len(n)>2 and n or ''
	end)
	return string.gsub(name, " ","")
end

function setcache(url, body)
	local cachedir = "/tmp/.cache/"
	lfs.mkdir( cachedir )
	local filename = string.gsub(url, "[/: ]", "-")
	
	f = io.open(cachedir .. filename, "w+")
	f:write(body)
	f:close()
	print'caching content'
	cache[url] = body
	
	return body, 200, cachedir .. filename
end

function getcache(url, code)
	local body = cache[url]
	if body then
		return body, 200
	end

	local cachedir = "./.cache/"
	lfs.mkdir( cachedir )
	local filename = string.gsub(url, "[/: ]", "-")
	
	f = io.open(cachedir .. filename, "r")
	if not f then
		return nil, code
	end
	local body = f:read'*a'
	f:close()
	print'got cached'
	return body, 200, cachedir .. filename
end

function cacheexpired(url)
	local cachedir = "./.cache/"
	lfs.mkdir( cachedir )
	local filename = string.gsub(url, "[/: ]", "-")
	
	local lastdate = lfs.attributes(cachedir .. filename, 'modification') or 0
	
	print('cached url:',url,  'expires on:', os.date("%d/%m/%Y %H:%M:%S",(tonumber(lastdate)  + tonumber(cacheduration))) )
	return not lastdate or (lastdate  + cacheduration) < os.time() 
end

function geturl(url, force)
	if force or cacheexpired(url) then
		body, code = http.request(url)
		if code == 200 and string.len(body) > 100 then
			return setcache(url, body)
		else
			return getcache(url, code)
		end
	else
		return getcache(url)
	end
end


function initialize()
	out:flush()
	body, c = geturl(baseurl )

	if c~=200 then
		print(string.format("Erro %s ao obter URL dos shows",tostring(c)))
		return 1
	end

	shows[normalize("StargateSG1")] = {
		name = "Stargate SG-1",
		url = baseurl 
	}
end

function grabseason(series, season, seasons)
	out:flush()
	local seasons = seasons or {}
	print'>>>>'
	table.foreach(shows, print)
	print(normalize(series))
	if not shows[normalize(series)] then
		return nil, "Cannot find the show " .. series
	end
	
	-- TODO: make season cache expire
	if shows[normalize(series)].seasons and shows[normalize(series)].seasons[season] then
		return shows[normalize(series)].seasons
	end
	
	local url = shows[normalize(series)].url
	local s = season

	url = string.gsub(url, "http://subtitles.stargate-sg1.hu/getsub.php[?]evad=(%d+)x&amp;nyelv=en&amp;mod=lista", function(ss)
		s = season or ss
		return "http://subtitles.stargate-sg1.hu/getsub.php?evad=".. tostring(s) .. "x&amp;nyelv=en&amp;mod=lista"
	end)
	seasons[s] = seasons[s] or {}
	body, c, h = geturl(url)
--print(body)
	string.gsub(body, '<a href="(http://felirat.csillagkapu.hu/subletolt.php[?]ID=%d+)" class=.%w+.>(%d+)x(%d+) ([^<]-)</a>', 
		function(url, season, episode,  name)
			season = tonumber(season)
			episode = tonumber(episode)
			--print(string.format("%dx%02d %s [%s]", season, episode, name, url))
			seasons[season] = seasons[season] or {}
			seasons[season][episode] = {
				name = name,
				rawurl = url
			}
		end)
	
	shows[normalize(series)].seasons = seasons
	
	return seasons
end

function addsub(episode, subfullpath, release, lang, ondisk)
	-- TODO: enhance the way we capture quality and dist from filename
	local _, __, quality, dist = string.find(release, "[(]([^).]-)[.]?([^).]-)[)]")
	quality, dist = quality or '', dist or ''
	
	local f = string.gfind(release, '%w+')
	local words = {}
	local word = f()
	while word do table.insert(words, word) word=f() end
	
	episode.subs = episode.subs  or {}
	local number = #episode.subs + 1
	episode.subs [number] = episode.subs[number] or {}
	episode.subs [number][lang] = {
		quality=normalize(quality),
		dist=normalize(dist),
		words=words
	}
	
	if ondisk then
		episode.subs [number][lang].path = subfullpath
	else
		episode.subs [number][lang].url = episode.rawurl
	end
	
end


function grabepisode(series, seasonno, episodeno, lang)
	out:flush()
	assert(series, 'must indicate series')
	seasonno = tonumber(seasonno)
	episodeno = tonumber(episodeno)
	lang = lang or 'en'
	lang = string.lower(lang)
	
	local seasons, msg = grabseason(series, seasonno)
	
	if not seasons then
		return nil, msg
	end
	
	if not (seasons and seasonno and episodeno) then
		return nil,'cannot load episode'
	end
	
	if not seasons[seasonno] then
		return nil, 'season does not exist'
	end
	
	if not seasons[seasonno][episodeno] then
		return nil, 'Episode subtitle cannot be downloaded'
	end
	
	local episode = seasons[seasonno][episodeno]
	addsub(episode, nil, '', lang, false)
	return episode, episode.subs and #episode.subs or 0
end

function choosebestsub(episode, file, language)
	log(2, 'Choosing  the best subtitles among ',episode.subs and #episode.subs ,' to',file.fileName)
	local language =  language or 'en'
	if episode.subs and #episode.subs > 0 then 
		table.foreach(episode.subs, function(_, l)
			local re = normalize(file.release)
			local sub = l[language]
			if sub then
				local qu = sub.quality
				local di = sub.dist
				local words = sub.words
				
				local pts = (string.find(re or '', qu or ':') and 2 or 0)
				pts = pts + (string.find(re or '', di or ':') and 3 or 0)
				
				for _,word in pairs(words) do
					pts = pts + (string.find(re or '', word or ':') and 1 or 0)
				end
				
				if sub.path then
				    print('lendo:', sub.path)
					local f = io.open(sub.path, 'r')
					if f then
						sub.text  = f:read'*a' or ''
						f:close()
						pts = pts + string.len(sub.text)>100 and 1 or -2
					else
						print'Could not  open file'
						pts  = -1
					end
				else
						pts = pts + 1
				end
				
				if not file.bestsub or (  file.bestsub.pts < pts ) then
					print'Chosen'
					file.bestsub = {
						pts = pts,
						sub=sub
					}
				end
			end
		end)
		return file
	else
		return nil, "No subtitles for " .. tostring(file.fileName)
	end
	
end


	
	
function loadsubtitles(files, language)
	out:flush()
	local language = language or 'en'
	local qtd = 0
	for _,file in pairs(files) do	
		local episode, subsno = grabepisode(file.series, file.season, file.episode, language)
		if not episode then
			return nil, subsno
		end 
		local ok, msg = choosebestsub(episode, file, language)
		if ok then
			print(file.bestsub.pts, file.bestsub.sub.quality, file.bestsub.sub.dist, file.bestsub.sub.url)
			local body, c, filename  = geturl(file.bestsub.sub.url)
			
			if not c==200 then
				return nil, 'could not obtain the subtitle url'
			end
			
			--[[
			if string.sub(body, 1,2)~='PK' then
				print'Getting script for downloading the file'
				local url = baseurl
				string.gsub(body, "var s%d-[^']+[']([^']+)[']", function(frag)
					url = url .. frag
				end)
				print('url:',url)
				body, c, filename = geturl(url)
			end
			]]
			
			
			if not filename then
				return nil, "Can't guess the subtitle filename"
			end
			
			zf = zip.open(filename)
			print('Opening Subtitle File', filename)
			if not zf then
				return nil, "Can't open zipfile"
			end

			for f in zf:files() do
				
				if string.find(f.filename, ".*[.][sS][rR][tT]") then
					print('File', f, f.filename)
					local ff = zf:open(f.filename)
					file.bestsub.sub.text = ff:read'*a' or ''
					ff:close()
					print('LOADED', 'length:', string.len(file.bestsub.sub.text) )
					qtd = qtd + 1
				end
			end
		else
			log(2, "There is no Subtitles [" .. tostring(language) .. " ] for " .. tostring(file.fileName))
		end
	end
	return qtd
end

initialize()
print(grabepisode(normalize("Stargate SG1"), 7, 12, "en"))
