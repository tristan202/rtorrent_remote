;==============================================================================
; Backend: Transmission via JSON-RPC (.../transmission/rpc) med Basic-auth
; Inkluderes af backend.pbi - brug Backend_*-procedurerne derfra.
;==============================================================================

Global gTRMutex = CreateMutex()
Global gTRSession.s       ; X-Transmission-Session-Id (beskyttet af gTRMutex)

; Accepterer fx https://host, https://host/transmission eller .../transmission/web/
Procedure.s TR_NormalizeUrl(u.s)
  Protected p.i, rest.s
  u = Trim(u)
  p = FindString(u, "://")
  If p = 0 : ProcedureReturn u : EndIf
  rest = Mid(u, p + 3)
  If FindString(rest, "/") = 0
    ProcedureReturn u + "/transmission/rpc"
  EndIf
  If Right(u, 1) = "/" : u = Left(u, Len(u) - 1) : EndIf
  If Right(LCase(u), 4) = "/web" : u = Left(u, Len(u) - 4) : EndIf
  If Right(LCase(u), 13) = "/transmission" : u + "/rpc" : EndIf
  ProcedureReturn u
EndProcedure

;------------------------------------------------------------------------------
; JSON
;------------------------------------------------------------------------------
Procedure.s JEsc(s.s)
  Protected i.i, c.i, r.s
  For i = 1 To Len(s)
    c = Asc(Mid(s, i, 1))
    Select c
      Case 34 : r + "\" + Chr(34)
      Case 92 : r + "\\"
      Case 0 To 31 : r + "\u" + RSet(Hex(c), 4, "0")
      Default : r + Chr(c)
    EndSelect
  Next
  ProcedureReturn Chr(34) + r + Chr(34)
EndProcedure

Procedure.s JIds(List h.s())
  Protected r.s = ""
  ForEach h()
    If r <> "" : r + "," : EndIf
    r + JEsc(h())
  Next
  ProcedureReturn "[" + r + "]"
EndProcedure

Procedure.q JQ(*o, key.s)
  Protected *v
  If *o = 0 : ProcedureReturn 0 : EndIf
  *v = GetJSONMember(*o, key)
  If *v = 0 : ProcedureReturn 0 : EndIf
  Select JSONType(*v)
    Case #PB_JSON_Number  : ProcedureReturn GetJSONQuad(*v)
    Case #PB_JSON_Boolean : ProcedureReturn GetJSONBoolean(*v)
  EndSelect
  ProcedureReturn 0
EndProcedure

Procedure.d JD(*o, key.s)
  Protected *v
  If *o = 0 : ProcedureReturn 0 : EndIf
  *v = GetJSONMember(*o, key)
  If *v And JSONType(*v) = #PB_JSON_Number : ProcedureReturn GetJSONDouble(*v) : EndIf
  ProcedureReturn 0
EndProcedure

Procedure.s JS(*o, key.s)
  Protected *v
  If *o = 0 : ProcedureReturn "" : EndIf
  *v = GetJSONMember(*o, key)
  If *v And JSONType(*v) = #PB_JSON_String : ProcedureReturn GetJSONString(*v) : EndIf
  ProcedureReturn ""
EndProcedure

;------------------------------------------------------------------------------
; HTTP. Transmission svarer 409 med en session-id, som skal sendes med igen.
;------------------------------------------------------------------------------
Procedure.s TR_SessionFromHeaders(headers.s)
  Protected i.i, n.i, ln.s
  headers = ReplaceString(headers, #CR$, "")
  n = CountString(headers, #LF$) + 1
  For i = 1 To n
    ln = StringField(headers, i, #LF$)
    If LCase(Left(ln, 26)) = "x-transmission-session-id:"
      ProcedureReturn Trim(Mid(ln, 27))
    EndIf
  Next
  ProcedureReturn ""
EndProcedure

Procedure.s TR_Http(*c.Conn, method.s, args.s)
  Protected NewMap hdr.s()
  Protected req.i, flags.i, resp.s, code.s, try.i, body.s
  body = "{" + JEsc("method") + ":" + JEsc(method)
  If args <> "" : body + "," + JEsc("arguments") + ":" + args : EndIf
  body + "}"
  If *c\noSSL : flags = #PB_HTTP_NoSSLCheck : EndIf
  LockMutex(gTRMutex)
  For try = 1 To 2
    ClearMap(hdr())
    hdr("Authorization") = BasicAuth(*c\user, *c\pass)
    hdr("Content-Type")  = "application/json"
    If gTRSession <> "" : hdr("X-Transmission-Session-Id") = gTRSession : EndIf
    req = HTTPRequest(#PB_HTTP_Post, *c\url, body, flags, hdr())
    If req = 0
      resp = "ERR:" + Lng("ErrConnect")
      Break
    EndIf
    code = HTTPInfo(req, #PB_HTTP_StatusCode)
    resp = HTTPInfo(req, #PB_HTTP_Response)
    If code = "409"
      gTRSession = TR_SessionFromHeaders(HTTPInfo(req, #PB_HTTP_Headers))
      FinishHTTP(req)
      resp = "ERR:HTTP 409 - " + Lng("ErrTR409")
      If gTRSession = "" : Break : EndIf
      Continue
    EndIf
    FinishHTTP(req)
    If code <> "200"
      If code = "401"
        resp = "ERR:HTTP 401 - " + Lng("ErrBadLogin")
      Else
        resp = "ERR:HTTP " + code + " - " + Lng("ErrCheckUrl", ".../transmission/rpc")
      EndIf
    EndIf
    Break
  Next
  UnlockMutex(gTRMutex)
  ProcedureReturn resp
EndProcedure

; Fejltekst fra et svar, eller "" hvis result = "success"
Procedure.s TR_Error(raw.s)
  Protected json.i, r.s
  If Left(raw, 4) = "ERR:" : ProcedureReturn Mid(raw, 5) : EndIf
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn Lng("ErrInvalidResponse", "Transmission") : EndIf
  r = JS(JSONValue(json), "result")
  FreeJSON(json)
  If r = "success" : ProcedureReturn "" : EndIf
  If r = "" : ProcedureReturn Lng("ErrInvalidResponse", "Transmission") : EndIf
  ProcedureReturn r
EndProcedure

Procedure.s TR_ListError(raw.s)
  ProcedureReturn TR_Error(raw)
EndProcedure

; Foerste torrent i arguments.torrents (bruges til detaljer)
Procedure.i TR_FirstTorrent(json.i)
  Protected *a
  *a = GetJSONMember(JSONValue(json), "arguments")
  If *a : *a = GetJSONMember(*a, "torrents") : EndIf
  If *a And JSONType(*a) = #PB_JSON_Array And JSONArraySize(*a) > 0
    ProcedureReturn GetJSONElement(*a, 0)
  EndIf
  ProcedureReturn 0
EndProcedure

Procedure.i TR_Array(*o, key.s)
  Protected *v
  If *o = 0 : ProcedureReturn 0 : EndIf
  *v = GetJSONMember(*o, key)
  If *v And JSONType(*v) = #PB_JSON_Array : ProcedureReturn *v : EndIf
  ProcedureReturn 0
EndProcedure

;------------------------------------------------------------------------------
; Torrent-liste
;------------------------------------------------------------------------------
#TR_ListFields = "hashString,name,sizeWhenDone,leftUntilDone,percentDone,rateDownload,rateUpload,uploadRatio,status,error,errorString,peersSendingToUs,peersConnected,labels,downloadDir,uploadedEver,downloadedEver,doneDate,secondsSeeding"

Procedure.s TR_Fields(list.s)
  Protected i.i, n.i = CountString(list, ",") + 1, r.s = ""
  For i = 1 To n
    If r <> "" : r + "," : EndIf
    r + JEsc(StringField(list, i, ","))
  Next
  ProcedureReturn "[" + r + "]"
EndProcedure

Procedure.s TR_FetchList(*c.Conn)
  ProcedureReturn TR_Http(*c, "torrent-get", "{" + JEsc("fields") + ":" + TR_Fields(#TR_ListFields) + "}")
EndProcedure

Procedure TR_ParseList(raw.s, List t.Torrent())
  Protected json.i, *arr, *o, *lb, i.i, j.i, st.i, r.d, lb.s
  ClearList(t())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = GetJSONMember(JSONValue(json), "arguments")
  *arr = TR_Array(*arr, "torrents")
  If *arr
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(t())
      t()\hash      = UCase(JS(*o, "hashString"))
      t()\name      = JS(*o, "name")
      t()\size      = JQ(*o, "sizeWhenDone")
      t()\leftB     = JQ(*o, "leftUntilDone")
      t()\done      = t()\size - t()\leftB
      t()\downRate  = JQ(*o, "rateDownload")
      t()\upRate    = JQ(*o, "rateUpload")
      r = JD(*o, "uploadRatio")          ; -1 = ikke tilgaengelig, -2 = uendelig
      If r < 0 : r = 0 : EndIf
      t()\ratio     = r * 1000
      t()\seeds     = JQ(*o, "peersSendingToUs")
      t()\peers     = JQ(*o, "peersConnected")
      t()\upTotal   = JQ(*o, "uploadedEver")
      t()\downTotal = JQ(*o, "downloadedEver")
      t()\dir       = JS(*o, "downloadDir")
      t()\finished  = JQ(*o, "doneDate")
      If JQ(*o, "error") <> 0 : t()\message = JS(*o, "errorString") : EndIf
      lb = ""
      *lb = TR_Array(*o, "labels")
      If *lb
        For j = 0 To JSONArraySize(*lb) - 1
          If lb <> "" : lb + ", " : EndIf
          lb + GetJSONString(GetJSONElement(*lb, j))
        Next
      EndIf
      t()\lbl = lb
      ; status: 0 stoppet, 1/2 tjek (i koe), 3/4 hent (i koe), 5/6 seed (i koe)
      st = JQ(*o, "status")
      t()\state    = Bool(st <> 0)
      t()\hashing  = Bool(st = 1 Or st = 2)
      t()\active   = 1
      t()\complete = Bool(JD(*o, "percentDone") >= 1.0 And t()\leftB = 0)
      ComputeTorrent(@t())
      If st = 3 Or st = 5 : t()\status = Lng("StQueued") : EndIf
      If t()\complete : t()\seedSecs = JQ(*o, "secondsSeeding") : EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

;------------------------------------------------------------------------------
; Detaljefaner (1 = trackere, 2 = peers, 3 = filer)
;------------------------------------------------------------------------------
Procedure.s TR_FetchDetails(*c.Conn, tab.i, hash.s)
  Protected f.s
  Select tab
    Case 1 : f = "trackerStats"
    Case 2 : f = "peers"
    Case 3 : f = "files,fileStats"
    Default : ProcedureReturn ""
  EndSelect
  ProcedureReturn TR_Http(*c, "torrent-get", "{" + JEsc("ids") + ":[" + JEsc(LCase(hash)) + "]," + JEsc("fields") + ":" + TR_Fields(f) + "}")
EndProcedure

Procedure TR_ParseTrackers(raw.s, List x.TrackerInfo())
  Protected json.i, *arr, *o, i.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = TR_Array(TR_FirstTorrent(json), "trackerStats")
  If *arr
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(x())
      x()\url       = JS(*o, "announce")
      x()\enabled   = 1
      x()\seeds     = JQ(*o, "seederCount")
      x()\peers     = JQ(*o, "leecherCount")
      x()\downloads = JQ(*o, "downloadCount")
      If x()\seeds < 0 : x()\seeds = 0 : EndIf
      If x()\peers < 0 : x()\peers = 0 : EndIf
      If x()\downloads < 0 : x()\downloads = 0 : EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

Procedure TR_ParsePeers(raw.s, List x.PeerInfo())
  Protected json.i, *arr, *o, i.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = TR_Array(TR_FirstTorrent(json), "peers")
  If *arr
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(x())
      x()\ip       = JS(*o, "address")
      x()\port     = JQ(*o, "port")
      x()\client   = JS(*o, "clientName")
      x()\progress = JD(*o, "progress") * 100
      x()\downRate = JQ(*o, "rateToClient")
      x()\upRate   = JQ(*o, "rateToPeer")
    Next
  EndIf
  FreeJSON(json)
EndProcedure

Procedure TR_ParseFiles(raw.s, List x.FileInfo())
  Protected json.i, *tor, *files, *stats, *o, *st, i.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *tor   = TR_FirstTorrent(json)
  *files = TR_Array(*tor, "files")
  *stats = TR_Array(*tor, "fileStats")
  If *files
    For i = 0 To JSONArraySize(*files) - 1
      *o = GetJSONElement(*files, i)
      AddElement(x())
      x()\path = JS(*o, "name")
      x()\size = JQ(*o, "length")
      x()\progress = 0
      If x()\size > 0 : x()\progress = JQ(*o, "bytesCompleted") * 100.0 / x()\size : EndIf
      x()\priority = 1
      If *stats And i < JSONArraySize(*stats)
        *st = GetJSONElement(*stats, i)
        If JQ(*st, "wanted") = 0
          x()\priority = 0
        ElseIf JQ(*st, "priority") > 0
          x()\priority = 2
        EndIf
      EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

;------------------------------------------------------------------------------
; Kommandoer
;------------------------------------------------------------------------------
Procedure.s TR_LowerIds(List h.s())
  Protected NewList l.s()
  ForEach h() : AddElement(l()) : l() = LCase(h()) : Next
  ProcedureReturn JIds(l())
EndProcedure

Procedure.s TR_Action(*c.Conn, act.i, List h.s())
  Protected method.s
  Select act
    Case #Act_Start   : method = "torrent-start"
    Case #Act_Stop    : method = "torrent-stop"
    Case #Act_Recheck : method = "torrent-verify"
    Default           : ProcedureReturn ""
  EndSelect
  ProcedureReturn TR_Error(TR_Http(*c, method, "{" + JEsc("ids") + ":" + TR_LowerIds(h()) + "}"))
EndProcedure

; Transmission sletter selv data (delete-local-data), saa der er ingen advarsler
Procedure.s TR_Remove(*c.Conn, List h.s(), withData.i, *warn.String)
  Protected e.s, del.s = "false"
  If withData : del = "true" : EndIf
  e = TR_Error(TR_Http(*c, "torrent-remove", "{" + JEsc("ids") + ":" + TR_LowerIds(h()) + "," + JEsc("delete-local-data") + ":" + del + "}"))
  If e <> "" : ProcedureReturn Lng("LblError") + ": " + e : EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s TR_AddArgs(key.s, value.s, start.i, dir.s)
  Protected a.s = "{" + JEsc(key) + ":" + JEsc(value) + "," + JEsc("paused") + ":"
  If start : a + "false" : Else : a + "true" : EndIf
  If dir <> "" : a + "," + JEsc("download-dir") + ":" + JEsc(dir) : EndIf
  ProcedureReturn a + "}"
EndProcedure

Procedure.s TR_AddFile(*c.Conn, *buf, size.i, start.i, dir.s)
  ProcedureReturn TR_Error(TR_Http(*c, "torrent-add", TR_AddArgs("metainfo", B64(*buf, size), start, dir)))
EndProcedure

Procedure.s TR_AddUrl(*c.Conn, url.s, start.i, dir.s)
  ProcedureReturn TR_Error(TR_Http(*c, "torrent-add", TR_AddArgs("filename", url, start, dir)))
EndProcedure

Procedure.s TR_Test(*c.Conn)
  Protected r.s, e.s, json.i, *a, msg.s
  msg = "URL: " + *c\url + #LF$ + Lng("TestUser") + ": " + *c\user + #LF$ + #LF$
  r = TR_Http(*c, "session-get", "{" + JEsc("fields") + ":" + TR_Fields("version,rpc-version,download-dir") + "}")
  e = TR_Error(r)
  If e <> ""
    ProcedureReturn msg + Lng("TestFailed", "session-get") + #LF$ + e
  EndIf
  json = ParseJSON(#PB_Any, r)
  If json
    *a = GetJSONMember(JSONValue(json), "arguments")
    msg + "Transmission " + JS(*a, "version") + " (" + Lng("TestRpcVersion") + " " + Str(JQ(*a, "rpc-version")) + ")" + #LF$
    msg + Lng("TestDefaultDir") + ": " + JS(*a, "download-dir")
    FreeJSON(json)
  EndIf
  ProcedureReturn msg
EndProcedure
