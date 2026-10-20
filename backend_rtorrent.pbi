;==============================================================================
; Backend: rTorrent via XML-RPC over HTTP(S) med Basic-auth
; Inkluderes af backend.pbi - brug Backend_*-procedurerne derfra.
;==============================================================================

#RT_NF_LIST = 20          ; antal felter pr. torrent i d.multicall2

Global gRpcMutex = CreateMutex()

Procedure.s RT_NormalizeUrl(u.s)
  Protected p.i, rest.s
  u = Trim(u)
  p = FindString(u, "://")
  If p
    rest = Mid(u, p + 3)
    If FindString(rest, "/") = 0 : u + "/RPC2" : EndIf
  EndIf
  ProcedureReturn u
EndProcedure

;------------------------------------------------------------------------------
; XML-RPC
;------------------------------------------------------------------------------
Procedure.s XmlEsc(s.s)
  s = ReplaceString(s, "&", "&amp;")
  s = ReplaceString(s, "<", "&lt;")
  s = ReplaceString(s, ">", "&gt;")
  ProcedureReturn s
EndProcedure

Procedure.s XmlUnesc(s.s)
  If FindString(s, "&") = 0 : ProcedureReturn s : EndIf
  s = ReplaceString(s, "&lt;", "<")
  s = ReplaceString(s, "&gt;", ">")
  s = ReplaceString(s, "&quot;", Chr(34))
  s = ReplaceString(s, "&apos;", "'")
  s = ReplaceString(s, "&amp;", "&")
  ProcedureReturn s
EndProcedure

Procedure.s PS(s.s)
  ProcedureReturn "<param><value><string>" + XmlEsc(s) + "</string></value></param>"
EndProcedure

Procedure.s MakeXml(method.s, params.s)
  ProcedureReturn "<?xml version=" + Chr(34) + "1.0" + Chr(34) + "?><methodCall><methodName>" + method + "</methodName><params>" + params + "</params></methodCall>"
EndProcedure

Procedure.s RT_Http(*c.Conn, body.s)
  Protected NewMap hdr.s()
  Protected req.i, flags.i, resp.s, code.s
  hdr("Authorization") = BasicAuth(*c\user, *c\pass)
  hdr("Content-Type")  = "text/xml"
  If *c\noSSL : flags = #PB_HTTP_NoSSLCheck : EndIf
  LockMutex(gRpcMutex)
  req = HTTPRequest(#PB_HTTP_Post, *c\url, body, flags, hdr())
  If req
    code = HTTPInfo(req, #PB_HTTP_StatusCode)
    resp = HTTPInfo(req, #PB_HTTP_Response)
    FinishHTTP(req)
    If code <> "200"
      If code = "401"
        resp = "ERR:HTTP 401 - " + Lng("ErrBadLogin")
      Else
        resp = "ERR:HTTP " + code + " - " + Lng("ErrCheckUrl", ".../RPC2")
      EndIf
    EndIf
  Else
    resp = "ERR:" + Lng("ErrConnect")
  EndIf
  UnlockMutex(gRpcMutex)
  ProcedureReturn resp
EndProcedure

; Udtraekker alle "blade" (string/i4/i8/...) i raekkefoelge
Procedure ParseLeaves(xml.s, List out.s())
  Protected pos.i = 1, lt.i, gt.i, endPos.i
  Protected tag.s, txt.s
  ClearList(out())
  Repeat
    lt = FindString(xml, "<", pos)
    If lt = 0 : Break : EndIf
    gt = FindString(xml, ">", lt)
    If gt = 0 : Break : EndIf
    tag = Mid(xml, lt + 1, gt - lt - 1)
    pos = gt + 1
    Select tag
      Case "string", "i4", "i8", "i2", "int", "boolean", "double", "base64"
        endPos = FindString(xml, "</" + tag + ">", pos)
        If endPos = 0 : Break : EndIf
        txt = Mid(xml, pos, endPos - pos)
        AddElement(out())
        out() = XmlUnesc(txt)
        pos = endPos + Len(tag) + 3
      Case "string/"
        AddElement(out())
        out() = ""
    EndSelect
  ForEver
EndProcedure

Procedure.s RT_Error(r.s)
  Protected NewList L.s()
  If Left(r, 4) = "ERR:" : ProcedureReturn Mid(r, 5) : EndIf
  If FindString(r, "<fault>")
    ParseLeaves(r, L())
    If LastElement(L()) : ProcedureReturn L() : EndIf
    ProcedureReturn Lng("ErrRTUnknown")
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s RT_ListCall()
  Protected f.s = "d.hash=,d.name=,d.size_bytes=,d.completed_bytes=,d.down.rate=,d.up.rate=,d.ratio=,d.state=,d.complete=,d.is_active=,d.peers_complete=,d.peers_accounted=,d.custom1=,d.message=,d.hashing=,d.left_bytes=,d.up.total=,d.down.total=,d.directory=,d.timestamp.finished="
  Protected p.s = PS("") + PS("main")
  Protected i.i
  For i = 1 To #RT_NF_LIST
    p + PS(StringField(f, i, ","))
  Next
  ProcedureReturn MakeXml("d.multicall2", p)
EndProcedure

; Sender flere kommandoer pr. torrent i ét kald (system.multicall)
Procedure.s RT_MultiCall(*c.Conn, methods.s, List hashes.s())
  Protected x.s, m.s, i.i, n.i = CountString(methods, "|") + 1
  x = "<param><value><array><data>"
  ForEach hashes()
    For i = 1 To n
      m = StringField(methods, i, "|")
      x + "<value><struct><member><name>methodName</name><value><string>" + m + "</string></value></member>"
      x + "<member><name>params</name><value><array><data><value><string>" + hashes() + "</string></value></data></array></value></member></struct></value>"
    Next
  Next
  x + "</data></array></value></param>"
  ProcedureReturn RT_Http(*c, MakeXml("system.multicall", x))
EndProcedure

Procedure.s RT_Load(*c.Conn, method.s, payload.s, dir.s)
  Protected p.s = PS("") + payload
  If dir <> ""
    p + PS("d.directory.set=" + Chr(34) + dir + Chr(34))
  EndIf
  ProcedureReturn RT_Http(*c, MakeXml(method, p))
EndProcedure

;------------------------------------------------------------------------------
; Torrent-liste. Svaret pakkes som "<servertid>" + LF + XML, fordi seedtiden
; beregnes ud fra serverens ur.
;------------------------------------------------------------------------------
Procedure.s RT_FetchList(*c.Conn)
  Protected resp.s, tm.s, srvT.q
  Protected NewList tl.s()
  resp = RT_Http(*c, RT_ListCall())
  If Left(resp, 4) = "ERR:" : ProcedureReturn resp : EndIf
  tm = RT_Http(*c, MakeXml("system.time", ""))
  ParseLeaves(tm, tl())
  If FirstElement(tl()) : srvT = Val(tl()) : EndIf
  ProcedureReturn Str(srvT) + #LF$ + resp
EndProcedure

Procedure.s RT_ListError(raw.s)
  If Left(raw, 4) = "ERR:" : ProcedureReturn Mid(raw, 5) : EndIf
  ProcedureReturn RT_Error(Mid(raw, FindString(raw, #LF$) + 1))
EndProcedure

Procedure RT_ParseList(raw.s, List t.Torrent())
  Protected NewList L.s()
  Protected Dim f.s(#RT_NF_LIST - 1)
  Protected idx.i = 0, srvT.q
  srvT = Val(StringField(raw, 1, #LF$))
  ParseLeaves(Mid(raw, FindString(raw, #LF$) + 1), L())
  ClearList(t())
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = #RT_NF_LIST
      idx = 0
      AddElement(t())
      t()\hash      = f(0)
      t()\name      = f(1)
      t()\size      = Val(f(2))
      t()\done      = Val(f(3))
      t()\downRate  = Val(f(4))
      t()\upRate    = Val(f(5))
      t()\ratio     = Val(f(6))
      t()\state     = Val(f(7))
      t()\complete  = Val(f(8))
      t()\active    = Val(f(9))
      t()\seeds     = Val(f(10))
      t()\peers     = Val(f(11))
      t()\lbl       = URLDecoder(f(12))
      t()\message   = f(13)
      t()\hashing   = Val(f(14))
      t()\leftB     = Val(f(15))
      t()\upTotal   = Val(f(16))
      t()\downTotal = Val(f(17))
      t()\dir       = f(18)
      t()\finished  = Val(f(19))
      ComputeTorrent(@t())
      If t()\complete And t()\finished > 0 And srvT > t()\finished
        t()\seedSecs = srvT - t()\finished
      EndIf
    EndIf
  Next
EndProcedure

;------------------------------------------------------------------------------
; Detaljefaner (1 = trackere, 2 = peers, 3 = filer)
;------------------------------------------------------------------------------
Procedure.s RT_FetchDetails(*c.Conn, tab.i, hash.s)
  Protected x.s
  Select tab
    Case 1
      x = MakeXml("t.multicall", PS(hash) + PS("") + PS("t.url=") + PS("t.is_enabled=") + PS("t.scrape_complete=") + PS("t.scrape_incomplete=") + PS("t.scrape_downloaded="))
    Case 2
      x = MakeXml("p.multicall", PS(hash) + PS("") + PS("p.address=") + PS("p.port=") + PS("p.client_version=") + PS("p.completed_percent=") + PS("p.down_rate=") + PS("p.up_rate="))
    Case 3
      x = MakeXml("f.multicall", PS(hash) + PS("") + PS("f.path=") + PS("f.size_bytes=") + PS("f.completed_chunks=") + PS("f.size_chunks=") + PS("f.priority="))
    Default
      ProcedureReturn ""
  EndSelect
  ProcedureReturn RT_Http(*c, x)
EndProcedure

Procedure RT_ParseTrackers(raw.s, List x.TrackerInfo())
  Protected NewList L.s()
  Protected Dim f.s(4)
  Protected idx.i = 0
  ParseLeaves(raw, L())
  ClearList(x())
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = 5
      idx = 0
      AddElement(x())
      x()\url       = f(0)
      x()\enabled   = Bool(f(1) = "1")
      x()\seeds     = Val(f(2))
      x()\peers     = Val(f(3))
      x()\downloads = Val(f(4))
    EndIf
  Next
EndProcedure

Procedure RT_ParsePeers(raw.s, List x.PeerInfo())
  Protected NewList L.s()
  Protected Dim f.s(5)
  Protected idx.i = 0
  ParseLeaves(raw, L())
  ClearList(x())
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = 6
      idx = 0
      AddElement(x())
      x()\ip       = f(0)
      x()\port     = Val(f(1))
      x()\client   = f(2)
      x()\progress = Val(f(3))
      x()\downRate = Val(f(4))
      x()\upRate   = Val(f(5))
    EndIf
  Next
EndProcedure

Procedure RT_ParseFiles(raw.s, List x.FileInfo())
  Protected NewList L.s()
  Protected Dim f.s(4)
  Protected idx.i = 0, tot.q
  ParseLeaves(raw, L())
  ClearList(x())
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = 5
      idx = 0
      AddElement(x())
      x()\path = f(0)
      x()\size = Val(f(1))
      tot = Val(f(3))
      x()\progress = 0
      If tot > 0 : x()\progress = Val(f(2)) * 100.0 / tot : EndIf
      Select Val(f(4))
        Case 0 : x()\priority = 0
        Case 2 : x()\priority = 2
        Default : x()\priority = 1
      EndSelect
    EndIf
  Next
EndProcedure

;------------------------------------------------------------------------------
; Kommandoer
;------------------------------------------------------------------------------
Procedure.s RT_Action(*c.Conn, act.i, List h.s())
  Protected methods.s
  Select act
    Case #Act_Start   : methods = "d.start|d.resume"
    Case #Act_Stop    : methods = "d.stop|d.close"
    Case #Act_Recheck : methods = "d.check_hash"
    Default           : ProcedureReturn ""
  EndSelect
  ProcedureReturn RT_Error(RT_MultiCall(*c, methods, h()))
EndProcedure

; Ekstra sikkerhedstjek foer der slettes noget paa serveren
Procedure.i SafeDataPath(path.s, nm.s)
  path = RTrim(path, "/")
  If nm = "" Or Left(path, 1) <> "/" : ProcedureReturn #False : EndIf
  If FindString(path, "..") : ProcedureReturn #False : EndIf
  If Right(path, Len(nm) + 1) <> "/" + nm : ProcedureReturn #False : EndIf
  If CountString(path, "/") < 4 : ProcedureReturn #False : EndIf
  ProcedureReturn #True
EndProcedure

; Fjerner torrents. Med withData stoppes de, data slettes paa serveren (rm -rf)
; og derefter fjernes torrenten. Returnerer en fejl (intet slettet / ikke fjernet),
; eller "" og evt. en advarsel i *warn.
Procedure.s RT_Remove(*c.Conn, List h.s(), withData.i, *warn.String)
  Protected NewList L.s()
  Protected r.s, e.s, path.s, nm.s, failed.s = "", idx.i = 0, skipped.i = 0, n.i = ListSize(h())

  If withData = #False
    e = RT_Error(RT_MultiCall(*c, "d.erase", h()))
    If e <> "" : ProcedureReturn Lng("LblError") + ": " + e : EndIf
    ProcedureReturn ""
  EndIf

  r = RT_MultiCall(*c, "d.base_path|d.name", h())
  e = RT_Error(r)
  If e <> ""
    ProcedureReturn Lng("ErrRTNoPath") + #LF$ + e + #LF$ + Lng("MsgNothingDeleted")
  EndIf
  ParseLeaves(r, L())
  If ListSize(L()) <> n * 2
    ProcedureReturn Lng("ErrRTBadPath") + #LF$ + Lng("MsgNothingDeleted")
  EndIf

  RT_MultiCall(*c, "d.stop|d.close", h())

  ForEach L()
    If idx % 2 = 0
      path = L()
    Else
      nm = L()
      If SafeDataPath(path, nm)
        r = RT_Http(*c, MakeXml("execute.nothrow.bg", PS("") + PS("rm") + PS("-rf") + PS("--") + PS(path)))
        e = RT_Error(r)
        If e <> "" : failed = e : EndIf
      Else
        skipped + 1
      EndIf
    EndIf
    idx + 1
  Next

  RT_MultiCall(*c, "d.erase", h())

  If failed <> ""
    *warn\s = Lng("WarnRTRmFailed") + #LF$ + failed + #LF$ + Lng("WarnRTLeftBehind")
  ElseIf skipped > 0
    *warn\s = Lng("WarnRTSkipped", Str(skipped)) + #LF$ + Lng("WarnRTRemovedAnyway")
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s RT_AddFile(*c.Conn, *buf, size.i, start.i, dir.s)
  Protected method.s = "load.raw_start"
  If start = #False : method = "load.raw" : EndIf
  ProcedureReturn RT_Error(RT_Load(*c, method, "<param><value><base64>" + B64(*buf, size) + "</base64></value></param>", dir))
EndProcedure

Procedure.s RT_AddUrl(*c.Conn, url.s, start.i, dir.s)
  Protected method.s = "load.start"
  If start = #False : method = "load.normal" : EndIf
  ProcedureReturn RT_Error(RT_Load(*c, method, PS(url), dir))
EndProcedure

Procedure.s RT_Test(*c.Conn)
  Protected r1.s, r2.s, msg.s
  r1 = RT_Http(*c, MakeXml("system.client_version", ""))
  msg = "URL: " + *c\url + #LF$ + Lng("TestUser") + ": " + *c\user + #LF$ + #LF$ + "system.client_version:" + #LF$ + Left(r1, 400)
  If Left(r1, 4) <> "ERR:" And RT_Error(r1) = ""
    r2 = RT_Http(*c, RT_ListCall())
    msg + #LF$ + #LF$ + "d.multicall2 (" + Lng("TestChars", Str(Len(r2))) + "):" + #LF$ + Left(r2, 500)
  EndIf
  ProcedureReturn msg
EndProcedure
