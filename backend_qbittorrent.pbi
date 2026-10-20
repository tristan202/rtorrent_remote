;==============================================================================
; Backend: qBittorrent via WebUI API v2 (.../api/v2/...) med cookie-login
; Inkluderes af backend.pbi efter backend_transmission.pbi (bruger JSON-hjaelperne).
;==============================================================================

Global gQBMutex = CreateMutex()
Global gQBCookie.s        ; "SID=..." fra auth/login (beskyttet af gQBMutex)
Global gQBCookieUrl.s     ; den server cookien hoerer til

; Basisadressen til WebUI, fx https://bruger.server.usbx.me/qbittorrent
Procedure.s QB_NormalizeUrl(u.s)
  Protected p.i
  u = Trim(u)
  p = FindString(LCase(u), "/api/v2")
  If p : u = Left(u, p - 1) : EndIf
  While Right(u, 1) = "/" : u = Left(u, Len(u) - 1) : Wend
  ProcedureReturn u
EndProcedure

; URL-kodning af en formularvaerdi (UTF-8, alt andet end A-Z a-z 0-9 - _ . ~ som %XX)
Procedure.s FormEnc(s.s)
  Protected *b, n.i, i.i, c.i, r.s
  n = StringByteLength(s, #PB_UTF8)
  If n = 0 : ProcedureReturn "" : EndIf
  *b = AllocateMemory(n + 2)
  PokeS(*b, s, -1, #PB_UTF8)
  For i = 0 To n - 1
    c = PeekA(*b + i)
    Select c
      Case 'A' To 'Z', 'a' To 'z', '0' To '9', '-', '_', '.', '~'
        r + Chr(c)
      Default
        r + "%" + RSet(Hex(c), 2, "0")
    EndSelect
  Next
  FreeMemory(*b)
  ProcedureReturn r
EndProcedure

Procedure.s QB_Hashes(List h.s())
  Protected r.s = ""
  ForEach h()
    If r <> "" : r + "|" : EndIf
    r + LCase(h())
  Next
  ProcedureReturn r
EndProcedure

;------------------------------------------------------------------------------
; HTTP. Kaldes med gQBMutex laast. Logger ind igen ved 403 (udloebet session).
;------------------------------------------------------------------------------
Procedure.s QB_CookieFromHeaders(headers.s)
  Protected i.i, n.i, ln.s, kv.s
  headers = ReplaceString(headers, #CR$, "")
  n = CountString(headers, #LF$) + 1
  For i = 1 To n
    ln = StringField(headers, i, #LF$)
    If LCase(Left(ln, 11)) = "set-cookie:"
      kv = Trim(StringField(Mid(ln, 12), 1, ";"))
      If FindString(UCase(StringField(kv, 1, "=")), "SID") : ProcedureReturn kv : EndIf
    EndIf
  Next
  ProcedureReturn ""
EndProcedure

; Returnerer "<statuskode>" + LF + svar, eller "ERR:..." hvis der ikke kunne forbindes
Procedure.s QB_Raw(*c.Conn, path.s, *data, size.i, contentType.s)
  Protected NewMap hdr.s()
  Protected req.i, flags.i, code.s, resp.s, url.s = *c\url + path
  If *c\noSSL : flags = #PB_HTTP_NoSSLCheck : EndIf
  hdr("Referer") = *c\url + "/"
  If gQBCookie <> "" : hdr("Cookie") = gQBCookie : EndIf
  If *data
    hdr("Content-Type") = contentType
    req = HTTPRequestMemory(#PB_HTTP_Post, url, *data, size, flags, hdr())
  Else
    req = HTTPRequest(#PB_HTTP_Get, url, "", flags, hdr())
  EndIf
  If req = 0 : ProcedureReturn "ERR:" + Lng("ErrConnect") : EndIf
  code = HTTPInfo(req, #PB_HTTP_StatusCode)
  resp = HTTPInfo(req, #PB_HTTP_Response)
  If path = "/api/v2/auth/login" And code = "200" And Trim(resp) = "Ok."
    gQBCookie = QB_CookieFromHeaders(HTTPInfo(req, #PB_HTTP_Headers))
    gQBCookieUrl = *c\url
  EndIf
  FinishHTTP(req)
  ProcedureReturn code + #LF$ + resp
EndProcedure

Procedure.s QB_RawForm(*c.Conn, path.s, form.s)
  Protected *b, n.i, r.s
  n = StringByteLength(form, #PB_UTF8)
  *b = AllocateMemory(n + 2)
  PokeS(*b, form, -1, #PB_UTF8)
  r = QB_Raw(*c, path, *b, n, "application/x-www-form-urlencoded")
  FreeMemory(*b)
  ProcedureReturn r
EndProcedure

Procedure.s QB_Login(*c.Conn)
  Protected r.s
  gQBCookie = ""
  r = QB_RawForm(*c, "/api/v2/auth/login", "username=" + FormEnc(*c\user) + "&password=" + FormEnc(*c\pass))
  If Left(r, 4) = "ERR:" : ProcedureReturn r : EndIf
  Select StringField(r, 1, #LF$)
    Case "200"
      If Trim(Mid(r, FindString(r, #LF$) + 1)) <> "Ok."
        ProcedureReturn "ERR:" + Lng("ErrQBBadLogin")
      EndIf
    Case "403"
      ProcedureReturn "ERR:" + Lng("ErrQBBanned")
    Default
      ProcedureReturn "ERR:HTTP " + StringField(r, 1, #LF$) + " " + Lng("ErrAtLogin") + " - " + Lng("ErrCheckUrl", ".../qbittorrent")
  EndSelect
  ProcedureReturn ""
EndProcedure

; Sender et kald (GET hvis *data = 0) og returnerer svaret eller "ERR:..."
Procedure.s QB_Call(*c.Conn, path.s, *data, size.i, contentType.s)
  Protected r.s, e.s, code.s, try.i
  LockMutex(gQBMutex)
  If gQBCookieUrl <> *c\url : gQBCookie = "" : EndIf
  For try = 1 To 2
    If gQBCookie = ""
      e = QB_Login(*c)
      If e <> "" : r = e : Break : EndIf
    EndIf
    r = QB_Raw(*c, path, *data, size, contentType)
    If Left(r, 4) = "ERR:" : Break : EndIf
    code = StringField(r, 1, #LF$)
    If code = "403" And try = 1
      gQBCookie = ""
      Continue
    EndIf
    If code = "200"
      r = Mid(r, FindString(r, #LF$) + 1)
    ElseIf code = "404"
      r = "ERR:HTTP 404 - " + Lng("ErrQB404")
    Else
      r = "ERR:HTTP " + code + " " + Trim(Mid(r, FindString(r, #LF$) + 1))
    EndIf
    Break
  Next
  UnlockMutex(gQBMutex)
  ProcedureReturn r
EndProcedure

Procedure.s QB_Get(*c.Conn, path.s)
  ProcedureReturn QB_Call(*c, path, 0, 0, "")
EndProcedure

Procedure.s QB_Post(*c.Conn, path.s, form.s)
  Protected *b, n.i, r.s
  n = StringByteLength(form, #PB_UTF8)
  *b = AllocateMemory(n + 2)
  PokeS(*b, form, -1, #PB_UTF8)
  r = QB_Call(*c, path, *b, n, "application/x-www-form-urlencoded")
  FreeMemory(*b)
  ProcedureReturn r
EndProcedure

; Fejltekst fra et svar, eller "" hvis det er gyldig JSON
Procedure.s QB_Error(raw.s)
  Protected json.i
  If Left(raw, 4) = "ERR:" : ProcedureReturn Mid(raw, 5) : EndIf
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn Lng("ErrInvalidResponse", "qBittorrent") : EndIf
  FreeJSON(json)
  ProcedureReturn ""
EndProcedure

Procedure.s QB_ListError(raw.s)
  ProcedureReturn QB_Error(raw)
EndProcedure

; Fejltekst fra et kommando-svar (tekst, ikke JSON)
Procedure.s QB_CmdError(raw.s)
  If Left(raw, 4) = "ERR:" : ProcedureReturn Mid(raw, 5) : EndIf
  If Trim(raw) = "Fails." : ProcedureReturn Lng("ErrQBRejected") : EndIf
  ProcedureReturn ""
EndProcedure

;------------------------------------------------------------------------------
; Torrent-liste
;------------------------------------------------------------------------------
Procedure.s QB_FetchList(*c.Conn)
  ProcedureReturn QB_Get(*c, "/api/v2/torrents/info")
EndProcedure

Procedure QB_ParseList(raw.s, List t.Torrent())
  Protected json.i, *arr, *o, i.i, st.s, r.d, cp.s
  ClearList(t())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = JSONValue(json)
  If JSONType(*arr) = #PB_JSON_Array
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(t())
      t()\hash      = UCase(JS(*o, "hash"))
      t()\name      = JS(*o, "name")
      t()\size      = JQ(*o, "size")
      t()\done      = JQ(*o, "completed")
      t()\leftB     = JQ(*o, "amount_left")
      t()\downRate  = JQ(*o, "dlspeed")
      t()\upRate    = JQ(*o, "upspeed")
      r = JD(*o, "ratio")
      If r < 0 : r = 0 : EndIf
      t()\ratio     = r * 1000
      t()\seeds     = JQ(*o, "num_seeds")
      t()\peers     = JQ(*o, "num_seeds") + JQ(*o, "num_leechs")
      t()\upTotal   = JQ(*o, "uploaded")
      t()\downTotal = JQ(*o, "downloaded")
      cp = JS(*o, "content_path")
      If cp = "" : cp = JS(*o, "save_path") : EndIf
      t()\dir       = cp
      t()\finished  = JQ(*o, "completion_on")
      t()\lbl       = JS(*o, "category")
      If t()\lbl = "" : t()\lbl = JS(*o, "tags") : EndIf
      ; qBittorrent 5 bruger stopped*, aeldre versioner paused*
      st = JS(*o, "state")
      t()\state    = Bool(Left(st, 7) <> "stopped" And Left(st, 6) <> "paused")
      t()\hashing  = Bool(Left(st, 8) = "checking")
      t()\active   = 1
      t()\complete = Bool(JD(*o, "progress") >= 1.0)
      Select st
        Case "error"       : t()\message = Lng("MsgTorrentError")
        Case "missingFiles" : t()\message = Lng("MsgFilesMissing")
      EndSelect
      ComputeTorrent(@t())
      Select st
        Case "queuedDL", "queuedUP" : t()\status = Lng("StQueued")
        Case "metaDL"               : t()\status = Lng("StMetadata")
        Case "moving"               : t()\status = Lng("StMoving")
        Case "error", "missingFiles" : t()\status = Lng("StError")
      EndSelect
      If t()\complete : t()\seedSecs = JQ(*o, "seeding_time") : EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

;------------------------------------------------------------------------------
; Detaljefaner (1 = trackere, 2 = peers, 3 = filer)
;------------------------------------------------------------------------------
Procedure.s QB_FetchDetails(*c.Conn, tab.i, hash.s)
  hash = LCase(hash)
  Select tab
    Case 1 : ProcedureReturn QB_Get(*c, "/api/v2/torrents/trackers?hash=" + hash)
    Case 2 : ProcedureReturn QB_Get(*c, "/api/v2/sync/torrentPeers?rid=0&hash=" + hash)
    Case 3 : ProcedureReturn QB_Get(*c, "/api/v2/torrents/files?hash=" + hash)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure QB_ParseTrackers(raw.s, List x.TrackerInfo())
  Protected json.i, *arr, *o, i.i, url.s
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = JSONValue(json)
  If JSONType(*arr) = #PB_JSON_Array
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      url = JS(*o, "url")
      If Left(url, 2) = "**" : Continue : EndIf   ; ** [DHT] **, ** [PeX] **, ** [LSD] **
      AddElement(x())
      x()\url       = url
      x()\enabled   = Bool(JQ(*o, "status") <> 0)
      x()\seeds     = JQ(*o, "num_seeds")
      x()\peers     = JQ(*o, "num_leeches")
      x()\downloads = JQ(*o, "num_downloaded")
      If x()\seeds < 0 : x()\seeds = 0 : EndIf
      If x()\peers < 0 : x()\peers = 0 : EndIf
      If x()\downloads < 0 : x()\downloads = 0 : EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

; sync/torrentPeers giver et objekt med "ip:port" som noegler
Procedure QB_ParsePeers(raw.s, List x.PeerInfo())
  Protected json.i, *peers, *o
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *peers = GetJSONMember(JSONValue(json), "peers")
  If *peers And JSONType(*peers) = #PB_JSON_Object
    If ExamineJSONMembers(*peers)
      While NextJSONMember(*peers)
        *o = JSONMemberValue(*peers)
        AddElement(x())
        x()\ip       = JS(*o, "ip")
        x()\port     = JQ(*o, "port")
        x()\client   = JS(*o, "client")
        x()\progress = JD(*o, "progress") * 100
        x()\downRate = JQ(*o, "dl_speed")
        x()\upRate   = JQ(*o, "up_speed")
      Wend
    EndIf
  EndIf
  FreeJSON(json)
EndProcedure

Procedure QB_ParseFiles(raw.s, List x.FileInfo())
  Protected json.i, *arr, *o, i.i, pr.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = JSONValue(json)
  If JSONType(*arr) = #PB_JSON_Array
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(x())
      x()\path     = JS(*o, "name")
      x()\size     = JQ(*o, "size")
      x()\progress = JD(*o, "progress") * 100
      pr = JQ(*o, "priority")         ; 0 = spring over, 1 = normal, 6/7 = hoej/maks
      If pr = 0
        x()\priority = 0
      ElseIf pr > 1
        x()\priority = 2
      Else
        x()\priority = 1
      EndIf
    Next
  EndIf
  FreeJSON(json)
EndProcedure

;------------------------------------------------------------------------------
; Kommandoer
;------------------------------------------------------------------------------
Procedure.s QB_Action(*c.Conn, act.i, List h.s())
  Protected form.s = "hashes=" + FormEnc(QB_Hashes(h())), r.s
  Select act
    Case #Act_Start
      r = QB_Post(*c, "/api/v2/torrents/start", form)
      If Left(r, 12) = "ERR:HTTP 404" : r = QB_Post(*c, "/api/v2/torrents/resume", form) : EndIf   ; qBittorrent 4.x
    Case #Act_Stop
      r = QB_Post(*c, "/api/v2/torrents/stop", form)
      If Left(r, 12) = "ERR:HTTP 404" : r = QB_Post(*c, "/api/v2/torrents/pause", form) : EndIf    ; qBittorrent 4.x
    Case #Act_Recheck
      r = QB_Post(*c, "/api/v2/torrents/recheck", form)
    Default
      ProcedureReturn ""
  EndSelect
  ProcedureReturn QB_CmdError(r)
EndProcedure

; qBittorrent sletter selv data (deleteFiles), saa der er ingen advarsler
Procedure.s QB_Remove(*c.Conn, List h.s(), withData.i, *warn.String)
  Protected e.s, del.s = "false"
  If withData : del = "true" : EndIf
  e = QB_CmdError(QB_Post(*c, "/api/v2/torrents/delete", "hashes=" + FormEnc(QB_Hashes(h())) + "&deleteFiles=" + del))
  If e <> "" : ProcedureReturn Lng("LblError") + ": " + e : EndIf
  ProcedureReturn ""
EndProcedure

; torrents/add kraever multipart/form-data. fileName = "" betyder ingen fil.
Procedure.s QB_Add(*c.Conn, urls.s, fileName.s, *buf, size.i, start.i, dir.s)
  Protected bnd.s = "----Torrentry" + Hex(Random($7FFFFFFF)) + Hex(ElapsedMilliseconds())
  Protected head.s = "", tail.s, stop.s = "true", *body, n1.i, n2.i, total.i, r.s
  If start : stop = "false" : EndIf
  If urls <> ""
    head + "--" + bnd + #CRLF$ + "Content-Disposition: form-data; name=" + Chr(34) + "urls" + Chr(34) + #CRLF$ + #CRLF$ + urls + #CRLF$
  EndIf
  ; "stopped" er navnet i qBittorrent 5, "paused" i aeldre versioner
  head + "--" + bnd + #CRLF$ + "Content-Disposition: form-data; name=" + Chr(34) + "stopped" + Chr(34) + #CRLF$ + #CRLF$ + stop + #CRLF$
  head + "--" + bnd + #CRLF$ + "Content-Disposition: form-data; name=" + Chr(34) + "paused" + Chr(34) + #CRLF$ + #CRLF$ + stop + #CRLF$
  If dir <> ""
    head + "--" + bnd + #CRLF$ + "Content-Disposition: form-data; name=" + Chr(34) + "savepath" + Chr(34) + #CRLF$ + #CRLF$ + dir + #CRLF$
  EndIf
  If fileName <> ""
    head + "--" + bnd + #CRLF$ + "Content-Disposition: form-data; name=" + Chr(34) + "torrents" + Chr(34) + "; filename=" + Chr(34) + ReplaceString(fileName, Chr(34), "_") + Chr(34) + #CRLF$
    head + "Content-Type: application/x-bittorrent" + #CRLF$ + #CRLF$
    tail = #CRLF$
  Else
    size = 0
  EndIf
  tail + "--" + bnd + "--" + #CRLF$
  n1 = StringByteLength(head, #PB_UTF8)
  n2 = StringByteLength(tail, #PB_UTF8)
  total = n1 + size + n2
  *body = AllocateMemory(total + 2)
  PokeS(*body, head, -1, #PB_UTF8 | #PB_String_NoZero)
  If size > 0 : CopyMemory(*buf, *body + n1, size) : EndIf
  PokeS(*body + n1 + size, tail, -1, #PB_UTF8 | #PB_String_NoZero)
  r = QB_Call(*c, "/api/v2/torrents/add", *body, total, "multipart/form-data; boundary=" + bnd)
  FreeMemory(*body)
  ProcedureReturn QB_CmdError(r)
EndProcedure

Procedure.s QB_AddFile(*c.Conn, *buf, size.i, start.i, dir.s)
  ProcedureReturn QB_Add(*c, "", "upload.torrent", *buf, size, start, dir)
EndProcedure

Procedure.s QB_AddUrl(*c.Conn, url.s, start.i, dir.s)
  ProcedureReturn QB_Add(*c, url, "", 0, 0, start, dir)
EndProcedure

Procedure.s QB_Test(*c.Conn)
  Protected v.s, api.s, sp.s, msg.s
  msg = "URL: " + *c\url + #LF$ + Lng("TestUser") + ": " + *c\user + #LF$ + #LF$
  v = QB_Get(*c, "/api/v2/app/version")
  If Left(v, 4) = "ERR:"
    ProcedureReturn msg + Lng("TestFailed", "app/version") + #LF$ + Mid(v, 5)
  EndIf
  api = QB_Get(*c, "/api/v2/app/webapiVersion")
  sp  = QB_Get(*c, "/api/v2/app/defaultSavePath")
  msg + "qBittorrent " + v + " (WebUI API " + api + ")" + #LF$
  msg + Lng("TestDefaultDir") + ": " + sp
  ProcedureReturn msg
EndProcedure
