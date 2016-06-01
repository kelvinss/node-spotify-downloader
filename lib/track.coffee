process = require("process")
async = require("async")
fs = require("fs")
mkdirp = require("mkdirp")
id3 = require("node-id3")
domain = require("domain")
request = require("request")
Path = require("path")
Logger = require("./log")
Logger = new Logger()
clone = require("clone")
sformat = require("string-format")
{objTypeof, deepMap, fixPathPiece, getSpotID} = require("./util")

class Track
	constructor: (@uri, @config, @data, @callback) ->
		@track = {}
		@file = {}
		@retryCounter = 0

	@setSpotify: (@spotify) ->

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
			try
				@createDirs()
			catch err
				Logger.Error "Error on track: \"#{@track.artist[0].name} - #{@track.name}\" : #{err} \n\n#{err.stack}"
				return @callback?()

	createDirs: =>
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
			return @callback?()

		if !_path.endsWith ".mp3"
			_path += ".mp3"

		@file.path = Path.join @config.directory, _path
		@file.directory = Path.dirname @file.path

		if fs.existsSync @file.path
			stats = fs.statSync @file.path
			if stats.size != 0
				Logger.Info "Already downloaded: #{@track.artist[0].name} - #{@track.name}", 1
				return @callback?()

		if !fs.existsSync @file.directory
			mkdirp.sync @file.directory

		Logger.Log "Downloading: #{@track.artist[0].name} - #{@track.name}", 1

		@downloadCover()
		@downloadFile()

	cleanDirs: (callback) =>
		clean = (fn, cb) =>
			fs.stat fn, (err, stats) =>
				if !err
					fs.unlink fn, cb
				else
					cb?()
		async.map [@file.path, "#{@file.path}.jpg"], clean, (err)->callback?(err)

	downloadCover: =>
		coverPath = "#{@file.path}.jpg"
		images = @track.album.coverGroup?.image
		image = images?[2] ? images?[0]
		if !image
			Logger.Error "Can't download cover: #{@track.artist[0].name} - #{@track.name}", 2
			return
		coverUrl = "#{image.uri}"
		request.get coverUrl
  	.on "error", (err) =>
    	Logger.Error "Error while downloading cover: #{err}"
  	.pipe fs.createWriteStream coverPath
		Logger.Success "Cover downloaded: #{@track.artist[0].name} - #{@track.name}", 2

	downloadFile: =>
		d = domain.create()
		d.on "error", (err) =>
			Logger.Error "Error received: #{err}", 2
			if "#{err}".indexOf("Rate limited") > -1
				if @retryCounter < 2
					@retryCounter++
					Logger.Info "#{err} ... { Retrying in 10 seconds }", 2
					setTimeout @downloadFile, 10000
				else
					@cleanDirs()
					Logger.Error "Unable to download song. Continuing", 2
					@callback?()
			else
				return @callback?()
		d.run =>
			@out = fs.createWriteStream @file.path
			try
				@strm = @track.play()
				@strm.pipe(@out).on "finish", =>
					@writeMetadata()
					Logger.Success "Done: #{@track.artist[0].name} - #{@track.name}", 2
					return @callback?()
			catch err
				@cleanDirs()
				Logger.Error "Error while downloading track! #{err}", 2
				@callback?()

	closeStream: (callback) => @strm?.unpipe(@out); callback?()

	writeMetadata: =>
		meta =
			artist: @track.artist[0].name
			album: @track.album.name
			title: @track.name
			year: "#{@track.album.date.year}"
			trackNumber: "#{@track.number}"
			image: "#{@file.path}.jpg"
		id3.write meta, @file.path
		fs.unlink meta.image

	padDigits = (number, digits) =>
    	return Array(Math.max(digits - String(number).length + 1, 0)).join(0) + number;

module.exports = Track
