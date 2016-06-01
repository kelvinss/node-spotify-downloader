
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

module.exports = { objTypeof, deepMap, fixPathPiece, getSpotID }
