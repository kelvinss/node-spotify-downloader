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
{objTypeof, deepMap, fixPathPiece} = require("./util")

class Track
	constructor: (@uri, @config, @callback) ->
		@track = {}
		@file = {}
		@retryCounter = 0

	@setSpotify: (@spotify) ->

	process: =>
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

		fields =
			track: trackCopy
			artist: trackCopy.artist[0]
			album: trackCopy.album
		fields.album.year = fields.album.date.year

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

	cleanDirs: =>
		fs.stat @file.path, (err, stats) =>
			if !err
				fs.unlink @file.path
		fs.stat "#{@file.path}.jpg", (err, stats) =>
			if !err
				fs.unlink "#{@file.path}.jpg"

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
			out = fs.createWriteStream @file.path
			try
				@track.play().pipe(out).on "finish", =>
					@writeMetadata()
					Logger.Success "Done: #{@track.artist[0].name} - #{@track.name}", 2
					return @callback?()
			catch err
				@cleanDirs()
				Logger.Error "Error while downloading track! #{err}", 2
				@callback?()

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

module.exports = Track
