process = require("process")
async = require("async")
fs = require("fs")
mkdirp = require("mkdirp")
id3 = require("node-id3")
domain = require("domain")
EventEmitter = require("events").EventEmitter
request = require("request")
Path = require("path")
Logger = require("./log")
Logger = new Logger()
clone = require("clone")
sformat = require("string-format")
{removeFile, objTypeof, deepMap, fixPathPiece, getSpotID} = require("./util")

class AlreadyDownloadedError

class Track
	constructor: (@uri, @config, @data, @callback) ->
		@track = {}
		@file = {}
		@retryCounter = 0

	@setSpotify: (@spotify) =>

	@init: () =>
		process.on "SIGINT", ()=>
			Logger.Log("\nCLOSING [SIGINT]")
			# @.cur?.cleanDirs (err) =>
			tasks = [@.cur?.closeStream, @.cur?.cleanDirs].map (f) => f ? (cb)->cb?()
			async.series tasks, (err) =>
				if err
					Logger.Error "Error while closing: #{err}"
				else
					Logger.Success "-- CLEANED --"
				process.exit(0)

	process: =>
		Track.cur = @
		@constructor.spotify.get @uri, (err, track) =>
#			restriction = track.restriction[0]
#			if !restriction.countriesForbidden? and restriction.countriesAllowed == ""
#				Logger.Error "Song is not available anymore."
#				@callback?()
			if err
				return @callback? err

			@track = track
			#@retryCounter = 0

			handleError = (err) =>
				Logger.Error "Error on track: \"#{@track.artist[0].name} - #{@track.name}\" : #{err} \n\n#{err.stack}"
				return @callback?()
			# @d = domain.create()
			# @d.on "error", (err) => console.log("ERROR MASTER DOMAIN"); handleError(err)##
			# @d.run =>
			try
				Logger.Log "Downloading: #{@track.artist[0].name} - #{@track.name}", 1
				@handle()
			catch err
				handleError(err)

	handle: =>
		#brk = => @cleanDirs(); @callback?()

		#@formatPath()
		#@handleFs()
		# @downloadFile =>
		# 	@downloadCover (err, hasCover) =>
		# 		@writeMetadata null, hasCover
		# 		@callback?()

		async.series [@formatPath, @handleFs, @downloadFile, @downloadCover, @writeMetadata], (err, res) =>
			if err
				if (err instanceof AlreadyDownloadedError)
					Logger.Info "Already downloaded: #{@track.artist[0].name} - #{@track.name}", 2
				else
					@cleanDirs()
			@callback?()

	formatPath: (callback) =>
		@config.directory = Path.resolve @config.directory

		if @config.folder and typeof @config.folder == "string"
			if @config.folder == "legacy"
				pathFormat = "{artist.name}/{album.name} [{album.year}]/{artist.name} - {track.name}" # maybe add "{track.number}"
			else
				pathFormat = @config.folder
		else
			pathFormat = "{artist.name} - {track.name}"
		#pathFormat ||= "{artist.name}\/{album.name} [{album.year}]\/{track.name}"

		trackCopy = clone(@track)
		trackCopy.name = trackCopy.name.replace(/\//g, " - ")

		fixStrg = (obj) =>
			if objTypeof(obj) == "[object String]"
				obj = obj.replace(/\//g, "-")
				if @config.onWindows
					obj = fixPathPiece(obj)
			obj
		deepMap.call({fn: fixStrg}, trackCopy)

		# Set IDs for track, album and artists
		o.id = getSpotID(o.uri) for o in [ trackCopy, trackCopy.album ].concat trackCopy.artist

		fields =
			track: trackCopy
			artist: trackCopy.artist[0]
			album: trackCopy.album
			playlist: {}
		fields.album.year = fields.album.date.year

		#if fields.track.number
		#	fields.track.number = padDigits(fields.track.number, String(@data.trackCount).length)
		if @data.type in ["album", "playlist", "library"]
			fields.playlist.name = @data.name
			fields.playlist.uri = @data.uri
			fields.playlist.id = @data.id
		if @data.type in ["playlist", "library"]
			fields.index = fields.track.index = padDigits(@data.index, String(@data.trackCount).length)
			fields.playlist.trackCount = @data.trackCount
			fields.playlist.user = @data.user

		fields.user = @config.username

		try
			_path = sformat pathFormat, fields
		catch err
			Logger.Error "Invalid path format: #{err}", 1
			#return @callback?()
			return callback?(err)

		if !_path.endsWith ".mp3"
			_path += ".mp3"

		@file.path = Path.join @config.directory, _path
		@file.directory = Path.dirname @file.path
		return callback?(err)

	handleFs: (callback) =>
		if fs.existsSync @file.path
			stats = fs.statSync @file.path
			if stats.size != 0
				return callback? new AlreadyDownloadedError()
				#return @callback?()

		if !fs.existsSync @file.directory
			mkdirp.sync @file.directory
		callback?()

	# cleanDirs: (callback) =>
	# 	removeFile(@file.path)
	# 	removeFile("#{@file.path}.jpg")
	# 	callback?()

	cleanDirs: (callback) =>
		# clean = (fn, cb) =>
		# 	fs.stat fn, (err, stats) =>
		# 		if !err
		# 			fs.unlink fn, cb
		# 		else
		# 			cb?()
		# async.map [@file.path, "#{@file.path}.jpg"], clean, (err)->callback?(err)
		async.map [@file.path, "#{@file.path}.jpg"], removeFile, callback

	downloadCover: (callback) =>
		coverPath = "#{@file.path}.jpg"
		images = @track.album.coverGroup?.image
		image = images?[2] ? images?[0]
		if !image
			Logger.Error "Can't download cover: #{@track.artist[0].name} - #{@track.name}", 2
			return callback?(null, @hasCover = false)
		coverUrl = "#{image.uri}"
		request.get coverUrl
		.on "error", (err) =>
			Logger.Error "Error while downloading cover: #{err}"
			callback?(null, @hasCover = false)
		.pipe fs.createWriteStream coverPath
		.on "finish", =>
			#@writeMetadata()
			Logger.Success "Cover downloaded: #{@track.artist[0].name} - #{@track.name}", 2
			callback?(null, @hasCover = true)

	downloadFile: (_callback) =>
		retries = 2
		retryTime = 10000

		# _callback = =>
		# 	@callback?()
		# 	_callback = ->

		callback = =>
			_callback?.apply(@,arguments)
			callback = ->

		func = () =>
			handleError = (err) =>
				if "#{err}".indexOf("Rate limited") > -1
					Logger.Error "Error received: #{err}", 2
					if @retryCounter < retries
						@retryCounter++
						Logger.Info "{ Retrying in #{retryTime/1000} seconds }", 2
						setTimeout(func, retryTime)
					else
						Logger.Error "Unable to download song: #{err}. Continuing", 2
						callback?(err)
				else
					#@cleanDirs()
					Logger.Error "Error while downloading track: \n#{err.stack}", 2
					callback?(err)

			d = domain.create()
			d.on "error", handleError
			d.run =>
				try
					@out = fs.createWriteStream @file.path
					@strm = @track.play()
					@strm.on "error", handleError
					@strm.pipe(@out).on "finish", =>
						Logger.Success "Downloaded: #{@track.artist[0].name} - #{@track.name}", 2
						callback?()
					if !Track.didRetry
						#@strm.unpipe(@out) ##
						#@strm.emit("error", new Error("Debug: Rate limited")) ##
						#@strm.emit("error", new Error("Debug")) ##
						Track.didRetry = 1
				catch err
					return handleError(err)

		func()

	closeStream: (callback) => @strm?.unpipe(@out); callback?()

	writeMetadata: (callback, hasCover) =>
		#throw	new Error("bizarre error")

		meta =
			artist: @track.artist[0].name
			album: @track.album.name
			title: @track.name
			year: "#{@track.album.date.year}"
			trackNumber: "#{@track.number}"
		if @hasCover
			meta.image = "#{@file.path}.jpg"
		id3.write meta, @file.path
		if @hasCover
			removeFile(meta.image)
		callback?()

	padDigits = (number, digits) =>
    	return Array(Math.max(digits - String(number).length + 1, 0)).join(0) + number;

module.exports = Track
