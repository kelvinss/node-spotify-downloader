
async = require("async")
fs = require("fs")
Path = require("path")


removeFile = (filename, callback) ->
	fs.stat filename, (err, stats) ->
		if !err
			fs.unlink filename, callback
		else
			callback?()

cleanEmptyDirs = (path, callback) ->
	stop = false
	func = (cb)->
		fs.rmdir path, (err)->
			if err
				if err.code == "ENOTEMPTY"
					stop = true
					return cb?()
				else if not err.code == "ENOENT"
					return cb?(err)
			path = Path.dirname(path)
			cb?()
	async.doUntil func, (->stop), (err)=>callback?(err)


makeB64 = (str) -> Buffer(str, "binary").toString("base64")


objTypeof = (obj) -> Object.prototype.toString.call(obj)

chkFn = (fn) -> if typeof fn == "function" then fn else (o)->o

deepMap = (obj) ->
	dp = deepMap.bind(@)
	if objTypeof(obj) == "[object Array]"
		chkFn(@array)( obj.map(dp) )
	else if objTypeof(obj) == "[object Object]"
		for own k,v of obj
			obj[k] = dp(v)
		chkFn(@object)(obj)
	else
		chkFn(@fn)(obj)

fixPathPiece = (piece) ->
	#piece.replace /[/\\?%*:|"<>]/g, ""
	piece.split(/[\/\\?%*:|"<>]/g).filter((i)->!!i).join(" ")

getSpotID = (uri) ->
	splitd = uri?.split(":") ? []
	if splitd[1] in ["track", "album", "artist"]
		return splitd[2]
	else if splitd[1] == "user" and splitd[3] == "playlist"
		return splitd[4]


module.exports = { removeFile, cleanEmptyDirs, makeB64, objTypeof, deepMap, fixPathPiece, getSpotID }
