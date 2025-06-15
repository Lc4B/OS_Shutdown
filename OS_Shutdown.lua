-------------- MPV OS Shutdown --------------
local options = require ("mp.options")
local input = require ("mp.input")
local utils = require ("mp.utils")

local o = {
	-- script di scansione della cartella attivi? (tipo autoload di uosc, che non inseriscono i file nella playlist)
	autoload = true,
	-- Estensioni utilizzate per capire se è l'ultimo file della cartella supportato da mpv (serve per autoload)
	-- (usiamo le estensioni di mpv (--directory-filter-types) ma deve seguire le impostazioni dell'autoload)
	use_video_exts = true,
    use_audio_exts = true,
    use_image_exts = false,
	-- Tramite exts si possono aggiungere estensioni manualmente alle precedenti. In caso le precedenti estensioni siano tutte disabilitate si può creare una lista personalizzata (utile per eventuali script black/white-list extensions)
	-- esempio: exts=mkv,mp4,avi,webm,mp3,flac,aac,ac3
	exts = false,
	-- Spegnimento alla fine della playlist con le impostazioni di default (keep-open e idle su no)
	end_playlist = true,
	-- Spegnimento alla chiusura (se vuoi che la chiusura di mpv inneschi uno spegnimento a prescindere se sia stato raggiunto nfiles)
	closing_shutdown = false,
	-- Tempo di attesa del timer per gli stati di stallo (keep-open o idle impostati) si può impostare su 0 per avere un funzionamento di end_playlist
	waiting_time = 1200,
	-- Sets keybinds for functions
	-- Key to activate the shutdown prompt
	set_key = "Ctrl+ì",
	-- Key to show shutdown info
	info_key = "Ctrl+^",
}

options.read_options(o)


local nfiles = 0
local num_eof = 0
local shut_switch = false
local check_switch = false
local keep_open = mp.get_property_native("keep-open")
local idle = mp.get_property_native("idle")

-- Funzione per ottenere le estensioni e combinarle
local function get_combined_extensions()
	if o.autoload == true then
		local extensions = {}
	
		if o.use_video_exts then
            local video_exts = mp.get_property_native("video-exts")
            table.move(video_exts, 1, #video_exts, #extensions + 1, extensions)
        end

        if o.use_audio_exts then
            local audio_exts = mp.get_property_native("audio-exts")
            table.move(audio_exts, 1, #audio_exts, #extensions + 1, extensions)
        end

        if o.use_image_exts then
            local image_exts = mp.get_property_native("image-exts")
            table.move(image_exts, 1, #image_exts, #extensions + 1, extensions)
        end
	
		-- Aggiunge le estensioni definite manualmente
		if o.exts and o.exts ~= "" then
			for ext in o.exts:gmatch("[^,]+") do  -- crea una tabella dalla stringa di estensioni
				table.insert(extensions, ext)
			end
		end
	
		return extensions
	end
end

local extensions = get_combined_extensions()

local function shutdown()
	local platform = mp.get_property_native("platform")  -- riconoscimento OS per come è stato creato mpv
	
	if platform == "windows" then
		mp.command_native({
			name = 'subprocess',
			args = {'shutdown', '/s', '/f', '/t', '0'},
			playback_only = false,
		})
	else
		mp.command_native({
			name = 'subprocess',
			args = {'sudo', 'shutdown', '-h', 'now'},  -- i permessi possono essere usati da mpv?
			playback_only = false,
		})
	end
	
	shut_switch = false  -- chiudi per evitare ulteriori comandi a spegnimento inviato
end

local timer = mp.add_timeout(o.waiting_time, function() shutdown() end, true)  -- timer di attesa per gli stati morti (keep-open o idle)

local function check_last()  -- controlla che non siano stati aggiunti file in coda durante l'ultimo file
	local playlist_len = mp.get_property_number("playlist-count")
	local current_index = mp.get_property_number("playlist-pos-1")
	
	if current_index == playlist_len then  -- se è sempre ultimo e non è stato aggiunto uno o più file in coda
		if keep_open ~= false then
			return true
		else
			num_eof = nfiles - 1  -- imposta come ultimo file da riprodurre
		end
	end

	check_switch = false  -- richiudere in ogni caso per evitare di raggiungerlo erroneamente
end

local function end_of_list(event, value)  -- fine dell'ultimo file per chi ha keep-open attivo
	if value == true then
		mp.unobserve_property(end_of_list)  -- corregge l'errore di multi-eof se successivamente si ricarica l'ultimo file
		if check_last() == true then
			if num_eof + 1 == nfiles then  -- ora non sovrascrivere num_eof, così si evita un doppio eof quando si cambiano o aggiungono file se non si è raggiunto nfiles
				num_eof = num_eof + 1  -- correggiamo num_eof, così evitiamo che durante lo spegnimento (quando viene chiuso mpv) si conti un altra volta l'ultimo eof
				shutdown()
			else
				timer:resume()  -- timer di uscita se non si raggiunge il numero di eof
			end
		end
	end
end

  -- ordinamento alfanumerico per umani in lua (sort_lua è la funzione principale)
  -- https://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
local function padnum(n, d)
	return #d > 0 and ('%03d%s%.12f'):format(#n, n, tonumber(d) / (10 ^ #d))
		or ('%03d%s'):format(#n, n)
end

local function sort_lua(strings)
	local tuples = {}
	for i, f in ipairs(strings) do
		tuples[i] = {f:lower():gsub('0*(%d+)%.?(%d*)', padnum), f}
	end
	table.sort(tuples, function(a, b)
		return a[1] == b[1] and #b[2] < #a[2] or a[1] < b[1]
	end)
	for i, tuple in ipairs(tuples) do strings[i] = tuple[2] end
	return strings
end

local function table_contains(table, element)  -- controlla se l'estensione del file è una delle estensioni della tabella, in caso restituisce true (aggiunto per evitare di mettere true a tutte le estensioni)
    for _, value in ipairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function readdir_sorted(path, extensions)
    local files = utils.readdir(path)  -- utils.readdir legge tutti i file nella cartella e li enumera
    local filtered_files = {}  -- tabella vuota che andremo a riempire con i nomi filtrati
    
    for _, file in ipairs(files) do  -- per ogni file
        local extension = file:match("%.([^.]+)$")  -- estrae l'estensione
        if extension and table_contains(extensions, extension) then  -- se l'estensione è presente nella tabella delle estensioni
            table.insert(filtered_files, file)  -- allora aggiungi il file nella tabella filtrata
        end
    end
    
    return sort_lua(filtered_files)  -- manda la tabella filtrata all'ordinamento
end
  -- fine ordinamento

local function check()  -- controlla se è l'ultimo file in playlist o cartella
	if timer:is_enabled() then
		timer:kill()  -- se siamo qui è stato caricato qualcos'altro manualmente dopo la fine dei file quindi rimuovere il timer
	end
	
	local playlist_len = mp.get_property_number("playlist-count")
	local current_index = mp.get_property_number("playlist-pos-1")
	
	if keep_open ~= false then  -- yes o always
		if playlist_len > 1 and current_index == playlist_len then
			mp.observe_property("eof-reached", "bool", end_of_list)
		end
		
		if playlist_len == 1 then
			if o.autoload == true then  -- riconoscere se è l'ultimo file nella cartella per la modalità autoload di uosc
				local curr_path = mp.get_property("path")  -- restituisce il percorso + il file
				local curr_dir, curr_file = utils.split_path(curr_path)  -- separa percorso e file
				
				local is_url = curr_path:match("^https?://") ~= nil  -- verifica se path è un URL
				
				if curr_path and not is_url then -- se restituisce un valore e non è un URL
					local files = readdir_sorted(curr_dir, extensions)  -- nomi dei file filtrati e ordinati
					list = files  -- variabile per la funzione info
					if files then
						local last_file = files[#files] -- files[#files] restituisce l'ultimo elemento dell'array (della tabella files)
						if last_file == curr_file then
							mp.observe_property("eof-reached", "bool", end_of_list)
						end
					end
				else
					mp.observe_property("eof-reached", "bool", end_of_list)  -- questo attiva il riconoscimento eof/timer per gli url
				end
			else
				mp.observe_property("eof-reached", "bool", end_of_list)
			end
		end
	else  -- keep-open=no
		if current_index == playlist_len then
			if idle ~= true then  -- no o once
				if o.end_playlist == true then
					check_switch = true  -- switch per il controllo nel finale
				end
			else  -- idle=yes
				if num_eof + 1 < nfiles then  -- se non sta per spegnere allora attiva il timer quando si va in idle
					mp.observe_property("idle-active", "bool", function(name, value)
						if value == true then
							timer:resume()
						end
					end)
				end
			end
		end
	end
end

local function end_of_file()
	num_eof = num_eof + 1
	if num_eof == nfiles then
		shutdown()
	end
end

local function input_number()
    input.get({
        prompt = 'Number of files:',
        submit = function(text)
			local number = tonumber(text)
			if number == nil then
				if shut_switch == true then
					mp.osd_message("Shutdown Deactivated")
				end
				shut_switch = false
				nfiles = 0
				num_eof = 0
				if timer:is_enabled() then
					timer:kill()
				end
				check_switch = false
			else
				if number < 1 then
					number = 1
				end
				if shut_switch == true then
					num_eof = 0
				end
				nfiles = number
				shut_switch = true
				check()  -- serve se stai attivando lo spegnimento durante l'ultimo file, senza non riconoscerebbe eof-reached
				mp.osd_message("Shutdown Activated" .. " (" .. nfiles .. ")")
			end
            input.terminate()
        end
    })
end

local function info()
	if shut_switch == true then
		local remaining = nfiles - num_eof - 1  -- -1 perchè contiamo i file rimanenti, indichiamo con 0 l'ultimo file che stiamo riproducendo
		local playlist_len = mp.get_property_number("playlist-count")
		
		if playlist_len == 1 and o.autoload == true then
			local curr_path = mp.get_property("path")
			local is_url = curr_path:match("^https?://") ~= nil
			
			if not is_url then
				local current = mp.get_property("filename")
				local last_index = #list  -- numero dell'ultimo file nella cartella
				local current_index = nil
				
				for i, v in ipairs(list) do  -- trova il numero del file attuale nella cartella
					if v == current then
						current_index = i
						break
					end
				end
				
				local remaining_folder = last_index - current_index
				if remaining < remaining_folder then
					mp.osd_message("Remaining files: " .. remaining, 2)
				else
					mp.osd_message("Remaining folder files: " .. remaining_folder .. " (" .. remaining .. ")", 2)
				end
			else
				mp.osd_message("Remaining items: " .. remaining, 2)
			end
		elseif keep_open == false and idle ~= true and o.end_playlist == true then
			local current_index = mp.get_property_number("playlist-pos-1")
			
			local remaining_playlist = playlist_len - current_index
			if remaining < remaining_playlist then
				mp.osd_message("Remaining media: " .. remaining, 2)
			else
				mp.osd_message("Remaining playlist entries: " .. remaining_playlist .. " (" .. remaining .. ")", 2)
			end
		elseif playlist_len == 0 then
			local remaining = nfiles - num_eof  -- se non ci sono file caricati credo sia sbagliato scalarne uno dai file rimanenti
			mp.osd_message("Remaining items: " .. remaining, 2)
		else
			mp.osd_message("Remaining items: " .. remaining, 2)
		end
	else
		mp.osd_message("Shutdown Off")
	end
end


mp.register_event("file-loaded", function()
	if shut_switch == true then
		check()
	end
end)
mp.register_event("end-file", function()
	if shut_switch == true then
		end_of_file()
	end
end)

mp.add_hook("on_unload", 50, function()
	if check_switch == true then
		check_last()
	end
end)

mp.register_event("shutdown", function()
	if shut_switch == true and o.closing_shutdown == true and num_eof < nfiles then
		shutdown()
	end
end)

mp.add_key_binding(o.set_key, "input_number", input_number)
mp.add_key_binding(o.info_key, "info", info)