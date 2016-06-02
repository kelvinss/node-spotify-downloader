# node-spotify-downloader

A community driven CLI and GUI solution to download music from Spotify
[![Join the chat at https://gitter.im/Lordmau5/node-spotify-downloader](https://badges.gitter.im/Lordmau5/node-spotify-downloader.svg)](https://gitter.im/Lordmau5/node-spotify-downloader?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Download entire Spotify playlists, albums or tracks (directly from Spotify at 160kbps) to your local machine.

### Features
- ID3 tags
- Album art image
- Download entire library
- Custom folder hierarchy

### Known problems
- ID3 tags don't work with Unicode characters
- Not possible to download 320kbps (limitation of Spotify Web)

### Prerequisites
- Install NodeJS **(v4.4.4 LTS)** if you haven't already. ([NodeJS Downloads](https://nodejs.org/en/))
- Download this repository as a .zip archive
- Unpack the contents to a folder of your choice
- Run `npm install` from a commandline

### CLI Usage

	Usage: node main.js [options]

	Options:

	    -h, --help                   output usage information
	    -V, --version                output the version number
	    -u, --username [username]    Spotify Username (required)
	    -p, --password [password]    Spotify Password (required)
	    -i, --uri 	   [URI / URL]   Spotify URI / URL for playlist, album or track - another valid input for this is "library"
	    -d, --directory [directory]  Download Directory - Default: "download" folder within the same directory
	    -f, --folder                 Create a sub-directory for playlist / album / library or specify folder hierarchy format


#### So
  If you wanted to download the playlist "Top 100 Hip-Hop Tracks on Spotify", you would use the following command:

	node main.js -u yourusername -p yourpassword -i spotify:user:spotify:playlist:06KmJWiQhL0XiV6QQAHsmw
	OR
	node main.js -u yourusername -p yourpassword -i https://play.spotify.com/user/spotify/playlist/06KmJWiQhL0XiV6QQAHsmw

  If you wanted to download the album "Epiphany", you would use the following command:

	node main.js -u yourusername -p yourpassword -i spotify:album:44Z1ZEmOyois0QoAgfUxrD
	OR
	node main.js -u yourusername -p yourpassword -i https://play.spotify.com/album/44Z1ZEmOyois0QoAgfUxrD

  If you wanted to download the track "2Pac I Get Around", you would use the following command:

	node main.js -u yourusername -p yourpassword -i spotify:track:74kHlIr01X459gqsSdNilW
	OR
	node main.js -u yourusername -p yourpassword -i https://play.spotify.com/track/74kHlIr01X459gqsSdNilW

#### Path format
If you pass `-f` flag without specifying a file path template, it will save the
songs inside a folder with the name of the album/playlist, or inside a `Library`
folder in case you are downloading all saved songs (`-i library`).

If you want to specify a path template, the following tokens are available:

- `{track.name}`
- `{track.number}`
- `{artist.name}`
- `{album.name}`
- `{album.year}`
- `{user}` (user name used for downloading)
- `{id}` (ID of what is being downloaded)
- `{b64uri}` (Spotify URI to be downloaded, base64 encoded)

In case of playlists and library, these tokens are also available:

- `{playlist.name}` ("Library" in case of library download)
- `{playlist.trackCount}` (the total number of tracks in the playlist or library)
- `{playlist.user}` (owner of the playlist)
- `{index}` (the index of the track in the playlist or library, not in the album it belogs to)

To get the ID of a track, album, artist or playlist, use the respective `.id` attribute (`{track.id}`, `{album.id}`, `{artist.id}`, or `{playlist.id}`).  
The same thing applies to the `.b64uri` attribute, which return a base64 version of the resource's URI.

e.g. `-f "{artist.name}/{album.name} [{album.year}]/{track.name}"`
will result in: `Rammstein/Mutter [2001]/Sonne.mp3`

e.g. `-f "{playlist.name}/{index} - {artist.name} - {track.name}"` for a playlist:
will result in `My playlist/18 - The Artist - The Song.mp3`

e.g. `-f "{artist.name} - {album.name} [{album.year}]/{track.number} - {artist.name} - {track.name}"` for an album:
will result in `The Artist - The Album [2015]/18 - The Artist - The Song.mp3`

Passing `-f legacy` will result in the format:
`{artist.name}/{album.name} [{album.year}]/{artist.name} - {track.name}`


### To run it from a Web browser
  To open in browser, just run from terminal/cmd file run.sh/run.bat (depends of your OS)
    this file will install all needed modules an start a local server (address will be displayed in terminal, by default is http://localhost:3001).
    Just open this address in your browser and ... enjoy :)


### Disclaimer
- Don't use it ( ͡° ͜ʖ ͡°)
