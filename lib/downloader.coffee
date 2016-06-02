Logger = require("./log")
Logger = new Logger()
Track = require("./track")
{makeB64, fixPathPiece} = require("./util")

fs = require("fs")
async = require("async")
lodash = require("lodash")
spotifyWeb = require("spotify-web")
EventEmitter = require("events").EventEmitter
Path = require('path')

class Downloader extends EventEmitter
	constructor: (@config) ->
		@data = {
			trackCount: 0
			type: null
		}

	fixPath: (path) =>
		path = path.replace(/\//g, "-")  # maybe this should be " - "
		if @config.onWindows
			path = fixPathPiece(path)
		path

	run: =>
		async.series [@login, @handleType, @handleDownload], (err, res) =>
			if err
				Logger.Log "#{res.toString()}"
				return Logger.Error "#{err.toString()}"

			Logger.Success ' ------- DONE ALL ------- '
			process.exit(0)

	login: (callback) =>
		spotifyWeb.login @config.username, @config.password, (err, SpotifyInstance) =>
			if err
				return Logger.Error "Error logging in... (#{err})"

			Logger.Success "Login successful!"

			@spotify = SpotifyInstance
			Track.setSpotify @spotify
			callback?()

	handleType: (callback) =>
		if @config.type == "playlist" # Good ol' playlists
			Logger.Log "Handling playlist ..."

			@spotify.playlist @config.uri, 0, 9001, (err, data) =>
				if err
					return Logger.Error "Playlist data error... #{err}"

				Logger.Log "Playlist: #{data.attributes.name}"

				@data.type = "playlist"
				@data.name = data.attributes.name

				@data.uri = @config.uri
				uriSplit = @config.uri.split(":")
				@data.user = uriSplit[2]
				@data.id = uriSplit[4]
				@data.b64uri = makeB64 @data.uri

				if @config.folder == true or @config.folder == ""
					@config.directory = Path.join @config.directory, @fixPath(@data.name)

				@data.tracks = lodash.map data.contents.items, (track) =>
					@data.trackCount += 1
					return track.uri

				callback?()

		else if @config.type == "album" # Albums! \o/
			Logger.Log "Handling album ..."

			@spotify.get @config.uri, (err, album) =>
				if err
					return Logger.Error "Album data error... #{err}"

				Logger.Log "Album: #{album.name}"

				@data.type = "album"
				@data.name = album.name
				@data.uri = @config.uri
				@data.id = @config.uri.split(":")[2]
				@data.b64uri = makeB64 @data.uri

				if @config.folder == true or @config.folder == ""
					@config.directory = Path.join @config.directory, @fixPath(@data.name)+" [#{album.date.year}]/"

				tracks = []
				album.disc.forEach (disc) =>
					if Array.isArray(disc.track)
						tracks.push.apply tracks, disc.track

				@data.tracks = lodash.map tracks, (track) =>
					@data.trackCount += 1
					return track.uri

				callback?()

		else if @config.type == "track" # Single tracks, aww yiss
			Logger.Log "Handling track ..."

			@data.type = "track"
			@data.tracks = [@config.uri]

			@data.uri = @config.uri
			@data.id = @config.uri.split(":")[2]
			@data.b64uri = makeB64 @data.uri

			@data.trackCount = 1

			callback?()

		else if @config.type == "library" # Saved tracks! :O
			Logger.Log "Handling library ..."

			@spotify.library @config.username, 0, 9001, (err, data) =>
				if err
					return Logger.Error "Library data error... #{err}"

				@data.type = "library"
				@data.name = "Library"
				@data.user = @config.username
				@data.uri = @data.id = "library"
				@data.b64uri = makeB64 @data.uri

				if @config.folder == true or @config.folder == ""
					@config.directory = Path.join @config.directory, "Library/"

				@data.tracks = lodash.map data.contents.items, (track) =>
					@data.trackCount += 1
					return track.uri

				callback?()

	handleDownload: (callback) =>
		Logger.Log "Processing #{@data.trackCount} tracks"

		Track.init()
		async.mapSeries @data.tracks, @processTrack, callback

	processTrack: (uri, callback) =>
		uriType = spotifyWeb.uriType uri
		if uriType == "local"
			Logger.Info "Skipping Local Track: #{uri}", 1
			return callback?()
		@data.index = @data.tracks.indexOf(uri) + 1
		new Track(uri, @config, @data, callback).process()

module.exports = Downloader
