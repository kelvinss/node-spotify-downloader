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
{cleanEmptyDirs, removeFile, makeB64, objTypeof, deepMap, fixPathPiece, getSpotID} = require("./util")

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

	handleAsyncError = (func) ->
	  ->
	    try
	      func.apply(this, arguments)
	    catch err
	      arguments[0]?(err)

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
			@handle()

	handle: =>
		Logger.Log "Downloading: #{@track.artist[0].name} - #{@track.name}", 1
		async.series [@formatPath, @handleFs, @downloadFile, @downloadCover, @writeMetadata], (err, res) =>
			if err
				if (err instanceof AlreadyDownloadedError)
					Logger.Info "Already downloaded: #{@track.artist[0].name} - #{@track.name}", 2
				else
					#Logger.Error "Error on track: \"#{@track.artist[0].name} - #{@track.name}\" : #{err} \n\n#{err.stack}"
					Logger.Error "Error on track: \"#{@track.artist[0].name} - #{@track.name}\" : #{err.stack}", 1
					return @cleanDirs(@callback)
			@callback?()

	formatPath: =>
	formatPath: handleAsyncError (callback) ->
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
		o.b64uri = makeB64 o.uri for o in [ trackCopy, trackCopy.album ].concat trackCopy.artist

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
			fields.playlist.b64uri = @data.b64uri

		if @data.type in ["playlist", "library"]
			fields.index = fields.track.index = padDigits(@data.index, String(@data.trackCount).length)
			fields.playlist.trackCount = @data.trackCount
			fields.playlist.user = @data.user

		fields.id = @data.id
		fields.b64uri = @data.b64uri
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

	handleFs: =>
	handleFs: handleAsyncError (callback) ->
		if fs.existsSync @file.path
			stats = fs.statSync @file.path
			if stats.size != 0
				return callback? new AlreadyDownloadedError()
				#return @callback?()

		if !fs.existsSync @file.directory
			mkdirp.sync @file.directory
		callback?()

	cleanDirs: (callback) =>
		if @file.path
			async.map [@file.path, "#{@file.path}.jpg"], removeFile, (err) => if err then callback?(err) else
				cleanEmptyDirs @file.directory, callback
		else
			callback?()

	downloadCover: =>
	downloadCover: handleAsyncError (callback) ->
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

	downloadFile: =>
	downloadFile: handleAsyncError (_callback) ->
		retries = 2
		retryTime = 10000

		callback = ->
			#d.exit()
			_callback?.apply(null,arguments)
			callback = ->

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
				#Logger.Error "Error while downloading track: \n#{err.stack}", 2
				Logger.Error "Error while downloading track: #{err}", 2
				callback?(err)

		func = () =>
			#d = domain.create()
			#d.on "error", handleError
			#d.run =>
			try
				@out = fs.createWriteStream @file.path
				@strm = @track.play()
				@strm.on "error", handleError
				@strm.pipe(@out).on "finish", =>
					Logger.Success "Downloaded: #{@track.artist[0].name} - #{@track.name}", 2
					callback?()
			catch err
				return handleError(err)

		func()

	closeStream: =>
	closeStream: handleAsyncError (_callback) ->
		callback = ->
			_callback(arguments...)
			callback = ->
		if @strm
			#@strm.unpipe(@out); callback?()
			@out.on "unpipe", =>callback?()
			@strm.on("error", callback).unpipe(@out)
		else
			callback?()

	writeMetadata: =>
	writeMetadata: handleAsyncError (callback) ->
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
