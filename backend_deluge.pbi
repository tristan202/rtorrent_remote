;==============================================================================
; Backend: Deluge via Web UI'ens JSON-RPC (.../json) med cookie-login.
; Web UI'en logger kun ind med en adgangskode og skal vaere forbundet til en
; daemon; er den ikke det, forbindes der til den foerste daemon i listen.
; Inkluderes af backend.pbi efter backend_transmission.pbi (bruger JSON-hjaelperne).
;==============================================================================

Global gDLMutex = CreateMutex()
Global gDLCookie.s        ; "_session_id=..." (beskyttet af gDLMutex)
Global gDLCookieUrl.s     ; den server cookien hoerer til
Global gDLId.i            ; loebenummer til JSON-RPC "id"

; Accepterer fx https://host/deluge, https://host/deluge/ eller .../deluge/json
Procedure.s DL_NormalizeUrl(u.s)
  u = Trim(u)
  While Right(u, 1) = "/" : u = Left(u, Len(u) - 1) : Wend
  If FindString(u, "://") = 0 : ProcedureReturn u : EndIf
  If Right(LCase(u), 5) <> "/json" : u + "/json" : EndIf
  ProcedureReturn u
EndProcedure

Procedure.s DL_CookieFromHeaders(headers.s)
  Protected i.i, n.i, ln.s
  headers = ReplaceString(headers, #CR$, "")
  n = CountString(headers, #LF$) + 1
  For i = 1 To n
    ln = StringField(headers, i, #LF$)
    If LCase(Left(ln, 11)) = "set-cookie:"
      ln = Trim(StringField(Mid(ln, 12), 1, ";"))
      If LCase(Left(ln, 12)) = "_session_id=" : ProcedureReturn ln : EndIf
    EndIf
  Next
  ProcedureReturn ""
EndProcedure

; Sender et kald. Kaldes med gDLMutex laast. Returnerer svaret eller "ERR:..."
Procedure.s DL_Raw(*c.Conn, method.s, params.s)
  Protected NewMap hdr.s()
  Protected req.i, flags.i, code.s, resp.s, body.s, ck.s
  gDLId + 1
  body = "{" + JEsc("method") + ":" + JEsc(method) + "," + JEsc("params") + ":" + params + "," + JEsc("id") + ":" + Str(gDLId) + "}"
  If *c\noSSL : flags = #PB_HTTP_NoSSLCheck : EndIf
  hdr("Content-Type") = "application/json"
  If gDLCookie <> "" : hdr("Cookie") = gDLCookie : EndIf
  req = HTTPRequest(#PB_HTTP_Post, *c\url, body, flags, hdr())
  If req = 0 : ProcedureReturn "ERR:" + Lng("ErrConnect") : EndIf
  code = HTTPInfo(req, #PB_HTTP_StatusCode)
  resp = HTTPInfo(req, #PB_HTTP_Response)
  ck = DL_CookieFromHeaders(HTTPInfo(req, #PB_HTTP_Headers))
  If ck <> "" : gDLCookie = ck : gDLCookieUrl = *c\url : EndIf
  FinishHTTP(req)
  If code <> "200"
    If code = "401"
      ProcedureReturn "ERR:HTTP 401 - " + Lng("ErrDLProxyAuth")
    EndIf
    ProcedureReturn "ERR:HTTP " + code + " - " + Lng("ErrCheckUrl", ".../deluge")
  EndIf
  ProcedureReturn resp
EndProcedure

; Fejlbesked og -kode fra et svar. Returnerer "" hvis "error" er null.
Procedure.s DL_ErrorOf(raw.s, *code.Integer = 0)
  Protected json.i, *e, msg.s
  If *code : *code\i = 0 : EndIf
  If Left(raw, 4) = "ERR:" : ProcedureReturn Mid(raw, 5) : EndIf
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn Lng("ErrInvalidResponse", "Deluge") : EndIf
  *e = GetJSONMember(JSONValue(json), "error")
  If *e And JSONType(*e) = #PB_JSON_Object
    msg = JS(*e, "message")
    If *code : *code\i = JQ(*e, "code") : EndIf
    If msg = "" : msg = Lng("ErrUnknownFrom", "Deluge") : EndIf
  EndIf
  FreeJSON(json)
  ProcedureReturn msg
EndProcedure

; Er "result" true?
Procedure.i DL_ResultTrue(raw.s)
  Protected json.i, *r, ok.i
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn #False : EndIf
  *r = GetJSONMember(JSONValue(json), "result")
  If *r And JSONType(*r) = #PB_JSON_Boolean : ok = GetJSONBoolean(*r) : EndIf
  FreeJSON(json)
  ProcedureReturn ok
EndProcedure

; Logger ind og soerger for at Web UI'en er forbundet til en daemon
Procedure.s DL_Login(*c.Conn)
  Protected r.s, e.s, json.i, *hosts, *h, id.s
  gDLCookie = ""
  r = DL_Raw(*c, "auth.login", "[" + JEsc(*c\pass) + "]")
  e = DL_ErrorOf(r)
  If e <> "" : ProcedureReturn "ERR:" + e : EndIf
  If DL_ResultTrue(r) = #False
    ProcedureReturn "ERR:" + Lng("ErrDLBadPass")
  EndIf
  r = DL_Raw(*c, "web.connected", "[]")
  If DL_ErrorOf(r) = "" And DL_ResultTrue(r) : ProcedureReturn "" : EndIf
  r = DL_Raw(*c, "web.get_hosts", "[]")
  e = DL_ErrorOf(r)
  If e <> "" : ProcedureReturn "ERR:" + e : EndIf
  json = ParseJSON(#PB_Any, r)
  If json
    *hosts = GetJSONMember(JSONValue(json), "result")
    If *hosts And JSONType(*hosts) = #PB_JSON_Array And JSONArraySize(*hosts) > 0
      *h = GetJSONElement(*hosts, 0)
      If JSONType(*h) = #PB_JSON_Array And JSONArraySize(*h) > 0
        id = GetJSONString(GetJSONElement(*h, 0))
      EndIf
    EndIf
    FreeJSON(json)
  EndIf
  If id = "" : ProcedureReturn "ERR:" + Lng("ErrDLNoDaemon") : EndIf
  e = DL_ErrorOf(DL_Raw(*c, "web.connect", "[" + JEsc(id) + "]"))
  If e <> "" : ProcedureReturn "ERR:" + Lng("ErrDLDaemon", e) : EndIf
  ProcedureReturn ""
EndProcedure

; Sender et kald og logger ind (igen) ved behov
Procedure.s DL_Call(*c.Conn, method.s, params.s)
  Protected r.s, e.s, code.Integer, try.i
  LockMutex(gDLMutex)
  If gDLCookieUrl <> *c\url : gDLCookie = "" : EndIf
  For try = 1 To 2
    If gDLCookie = ""
      e = DL_Login(*c)
      If e <> "" : r = e : Break : EndIf
    EndIf
    r = DL_Raw(*c, method, params)
    If Left(r, 4) = "ERR:" : Break : EndIf
    DL_ErrorOf(r, @code)
    If code\i = 1 And try = 1          ; "Not authenticated" - sessionen er udloebet
      gDLCookie = ""
      Continue
    EndIf
    Break
  Next
  UnlockMutex(gDLMutex)
  ProcedureReturn r
EndProcedure

Procedure.s DL_Error(raw.s)
  ProcedureReturn DL_ErrorOf(raw)
EndProcedure

Procedure.s DL_ListError(raw.s)
  ProcedureReturn DL_ErrorOf(raw)
EndProcedure

Procedure.i DL_Result(json.i)
  ProcedureReturn GetJSONMember(JSONValue(json), "result")
EndProcedure

Procedure.s DL_Ids(List h.s())
  Protected NewList l.s()
  ForEach h() : AddElement(l()) : l() = LCase(h()) : Next
  ProcedureReturn JIds(l())
EndProcedure

;------------------------------------------------------------------------------
; Torrent-liste
;------------------------------------------------------------------------------
#DL_ListFields = "name,total_wanted,total_done,progress,download_payload_rate,upload_payload_rate,ratio,state,num_seeds,num_peers,label,message,save_path,total_uploaded,all_time_download,completed_time,seeding_time,is_finished"

Procedure.s DL_FetchList(*c.Conn)
  ProcedureReturn DL_Call(*c, "core.get_torrents_status", "[{}," + TR_Fields(#DL_ListFields) + "]")
EndProcedure

Procedure DL_ParseList(raw.s, List t.Torrent())
  Protected json.i, *res, *o, st.s, r.d
  ClearList(t())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *res = DL_Result(json)
  If *res And JSONType(*res) = #PB_JSON_Object And ExamineJSONMembers(*res)
    While NextJSONMember(*res)
      *o = JSONMemberValue(*res)
      AddElement(t())
      t()\hash      = UCase(JSONMemberKey(*res))
      t()\name      = JS(*o, "name")
      t()\size      = JQ(*o, "total_wanted")
      t()\done      = JQ(*o, "total_done")
      t()\leftB     = t()\size - t()\done
      If t()\leftB < 0 : t()\leftB = 0 : EndIf
      t()\downRate  = JQ(*o, "download_payload_rate")
      t()\upRate    = JQ(*o, "upload_payload_rate")
      r = JD(*o, "ratio")
      If r < 0 : r = 0 : EndIf
      t()\ratio     = r * 1000
      t()\seeds     = JQ(*o, "num_seeds")
      t()\peers     = JQ(*o, "num_seeds") + JQ(*o, "num_peers")
      t()\upTotal   = JQ(*o, "total_uploaded")
      t()\downTotal = JQ(*o, "all_time_download")
      t()\dir       = JS(*o, "save_path")
      t()\finished  = JQ(*o, "completed_time")
      t()\lbl       = JS(*o, "label")
      st = JS(*o, "state")
      If st = "Error" : t()\message = JS(*o, "message") : EndIf
      t()\state    = Bool(st <> "Paused")
      t()\hashing  = Bool(st = "Checking")
      t()\active   = 1
      t()\complete = Bool(JQ(*o, "is_finished") Or JD(*o, "progress") >= 100.0)
      ComputeTorrent(@t())
      Select st
        Case "Queued"     : t()\status = Lng("StQueued")
        Case "Moving"     : t()\status = Lng("StMoving")
        Case "Allocating" : t()\status = Lng("StAllocating")
        Case "Error"      : t()\status = Lng("StError")
      EndSelect
      If t()\complete : t()\seedSecs = JQ(*o, "seeding_time") : EndIf
    Wend
  EndIf
  FreeJSON(json)
EndProcedure

;------------------------------------------------------------------------------
; Detaljefaner (1 = trackere, 2 = peers, 3 = filer)
;------------------------------------------------------------------------------
Procedure.s DL_FetchDetails(*c.Conn, tab.i, hash.s)
  Protected f.s
  Select tab
    Case 1 : f = "trackers"
    Case 2 : f = "peers"
    Case 3 : f = "files,file_progress,file_priorities"
    Default : ProcedureReturn ""
  EndSelect
  ProcedureReturn DL_Call(*c, "core.get_torrent_status", "[" + JEsc(LCase(hash)) + "," + TR_Fields(f) + "]")
EndProcedure

Procedure DL_ParseTrackers(raw.s, List x.TrackerInfo())
  Protected json.i, *arr, *o, i.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = TR_Array(DL_Result(json), "trackers")
  If *arr
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(x())
      x()\url     = JS(*o, "url")
      x()\enabled = 1                  ; Deluge giver ikke seeds/peers pr. tracker
    Next
  EndIf
  FreeJSON(json)
EndProcedure

Procedure DL_ParsePeers(raw.s, List x.PeerInfo())
  Protected json.i, *arr, *o, i.i, ip.s, p.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *arr = TR_Array(DL_Result(json), "peers")
  If *arr
    For i = 0 To JSONArraySize(*arr) - 1
      *o = GetJSONElement(*arr, i)
      AddElement(x())
      ip = JS(*o, "ip")                ; "1.2.3.4:6881" eller "[::1]:6881"
      p = FindString(ReverseString(ip), ":")
      If p
        p = Len(ip) - p + 1
        x()\port = Val(Mid(ip, p + 1))
        ip = Left(ip, p - 1)
      EndIf
      x()\ip       = RemoveString(RemoveString(ip, "["), "]")
      x()\client   = JS(*o, "client")
      x()\progress = JD(*o, "progress") * 100
      x()\downRate = JQ(*o, "down_speed")
      x()\upRate   = JQ(*o, "up_speed")
    Next
  EndIf
  FreeJSON(json)
EndProcedure

Procedure DL_ParseFiles(raw.s, List x.FileInfo())
  Protected json.i, *res, *files, *prog, *prio, *o, i.i, pr.i
  ClearList(x())
  json = ParseJSON(#PB_Any, raw)
  If json = 0 : ProcedureReturn : EndIf
  *res   = DL_Result(json)
  *files = TR_Array(*res, "files")
  *prog  = TR_Array(*res, "file_progress")
  *prio  = TR_Array(*res, "file_priorities")
  If *files
    For i = 0 To JSONArraySize(*files) - 1
      *o = GetJSONElement(*files, i)
      AddElement(x())
      x()\path = JS(*o, "path")
      x()\size = JQ(*o, "size")
      If *prog And i < JSONArraySize(*prog) : x()\progress = GetJSONDouble(GetJSONElement(*prog, i)) * 100 : EndIf
      x()\priority = 1
      If *prio And i < JSONArraySize(*prio)
        pr = GetJSONInteger(GetJSONElement(*prio, i))   ; 0 = spring over, 1 = lav, 4 = normal, 7 = hoej
        If pr = 0
          x()\priority = 0
        ElseIf pr > 4
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
Procedure.s DL_Action(*c.Conn, act.i, List h.s())
  Protected method.s
  Select act
    Case #Act_Start   : method = "core.resume_torrents"
    Case #Act_Stop    : method = "core.pause_torrents"
    Case #Act_Recheck : method = "core.force_recheck"
    Default           : ProcedureReturn ""
  EndSelect
  ProcedureReturn DL_ErrorOf(DL_Call(*c, method, "[" + DL_Ids(h()) + "]"))
EndProcedure

; Deluge sletter selv data (remove_data), saa der er ingen advarsler
Procedure.s DL_Remove(*c.Conn, List h.s(), withData.i, *warn.String)
  Protected r.s, e.s, del.s = "false", json.i, *res, n.i
  If withData : del = "true" : EndIf
  r = DL_Call(*c, "core.remove_torrents", "[" + DL_Ids(h()) + "," + del + "]")
  e = DL_ErrorOf(r)
  If e <> "" : ProcedureReturn Lng("LblError") + ": " + e : EndIf
  ; resultatet er en liste over de torrents, der ikke kunne fjernes
  json = ParseJSON(#PB_Any, r)
  If json
    *res = DL_Result(json)
    If *res And JSONType(*res) = #PB_JSON_Array : n = JSONArraySize(*res) : EndIf
    FreeJSON(json)
  EndIf
  If n > 0 : ProcedureReturn Lng("LblError") + ": " + Lng("ErrNotRemoved", Str(n)) : EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s DL_Options(start.i, dir.s)
  Protected o.s = "{" + JEsc("add_paused") + ":"
  If start : o + "false" : Else : o + "true" : EndIf
  If dir <> "" : o + "," + JEsc("download_location") + ":" + JEsc(dir) : EndIf
  ProcedureReturn o + "}"
EndProcedure

Procedure.s DL_AddFile(*c.Conn, *buf, size.i, start.i, dir.s)
  ProcedureReturn DL_ErrorOf(DL_Call(*c, "core.add_torrent_file", "[" + JEsc("upload.torrent") + "," + JEsc(B64(*buf, size)) + "," + DL_Options(start, dir) + "]"))
EndProcedure

Procedure.s DL_AddUrl(*c.Conn, url.s, start.i, dir.s)
  Protected method.s = "core.add_torrent_url"
  If LCase(Left(url, 7)) = "magnet:" : method = "core.add_torrent_magnet" : EndIf
  ProcedureReturn DL_ErrorOf(DL_Call(*c, method, "[" + JEsc(url) + "," + DL_Options(start, dir) + "]"))
EndProcedure

Procedure.s DL_Test(*c.Conn)
  Protected r.s, e.s, json.i, msg.s
  msg = "URL: " + *c\url + #LF$ + #LF$
  r = DL_Call(*c, "daemon.info", "[]")
  e = DL_ErrorOf(r)
  If e <> "" : ProcedureReturn msg + Lng("TestFailed", "daemon.info") + #LF$ + e : EndIf
  json = ParseJSON(#PB_Any, r)
  If json
    If DL_Result(json) And JSONType(DL_Result(json)) = #PB_JSON_String
      msg + "Deluge " + GetJSONString(DL_Result(json)) + #LF$
    EndIf
    FreeJSON(json)
  EndIf
  r = DL_Call(*c, "core.get_config_value", "[" + JEsc("download_location") + "]")
  json = ParseJSON(#PB_Any, r)
  If json
    If DL_Result(json) And JSONType(DL_Result(json)) = #PB_JSON_String
      msg + Lng("TestDefaultDir") + ": " + GetJSONString(DL_Result(json))
    EndIf
    FreeJSON(json)
  EndIf
  ProcedureReturn msg
EndProcedure
