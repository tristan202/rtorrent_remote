;==============================================================================
; rTorrent Remote - Windows-klient i PureBasic (qBittorrent-lignende)
;
; Krav:   PureBasic 6.x (x64 anbefales)
;         Compiler > Compiler Options > "Create threadsafe executable" = TIL
; Server: rTorrent med XML-RPC over HTTP(S) og Basic-auth, f.eks. Ultra.cc:
;         https://BRUGER.SERVER.usbx.me/RPC2
;==============================================================================
EnableExplicit

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Slaa 'Create threadsafe executable' til (Compiler > Compiler Options)."
CompilerEndIf

#APP_NAME           = "rTorrent Remote"
#NF_LIST            = 20          ; antal felter pr. torrent i d.multicall2
#MY_LVN_COLUMNCLICK = -108

#EvPoll = #PB_Event_FirstCustomValue
#EvSort = #PB_Event_FirstCustomValue + 1
#EvHdrMenu = #PB_Event_FirstCustomValue + 2
#M_ColBase = 100
#MY_COL_PROGRESS = 2
CompilerIf #PB_Compiler_64Bit
  #MY_OFF_STAGE = 24
  #MY_OFF_HDC   = 32
  #MY_OFF_ITEM  = 56
  #MY_OFF_SUB   = 88
CompilerElse
  #MY_OFF_STAGE = 12
  #MY_OFF_HDC   = 16
  #MY_OFF_ITEM  = 36
  #MY_OFF_SUB   = 56
CompilerEndIf

Enumeration 1
  #Win
  #WinSrv
  #WinMag
EndEnumeration

Enumeration 1
  ; hovedvindue
  #G_BtnAddFile
  #G_BtnAddMagnet
  #G_BtnStart
  #G_BtnStop
  #G_BtnRemove
  #G_Server
  #G_BtnServers
  #G_SearchLbl
  #G_Search
  #G_Filter
  #G_List
  #G_Panel
  #G_General
  #G_Trackers
  #G_Peers
  #G_Files
  ; server-dialog
  #G_SrvList
  #G_SrvName
  #G_SrvUrl
  #G_SrvUser
  #G_SrvPass
  #G_SrvNoSSL
  #G_SrvNew
  #G_SrvSave
  #G_SrvDel
  #G_SrvClose
  ; magnet-dialog
  #G_MagText
  #G_MagDir
  #G_MagStart
  #G_MagOK
  #G_MagCancel
EndEnumeration

Enumeration 1
  #M_AddFile
  #M_AddMagnet
  #M_Quit
  #M_Start
  #M_Stop
  #M_StartAll
  #M_StopAll
  #M_Recheck
  #M_RemoveTorrent
  #M_RemoveData
  #M_Servers
  #M_Refresh
  #M_Test
  #M_About
  #M_Sidebar
EndEnumeration

Structure Server
  name.s
  url.s
  user.s
  pass.s
  noSSL.i
EndStructure

Structure Torrent
  hash.s
  name.s
  size.q
  done.q
  leftB.q
  downRate.q
  upRate.q
  ratio.q
  upTotal.q
  downTotal.q
  eta.q
  finished.q
  seedSecs.q
  progress.d
  state.l
  complete.l
  active.l
  hashing.l
  seeds.l
  peers.l
  lbl.s
  message.s
  dir.s
  status.s
EndStructure

Structure MY_NMLV
  hdr.NMHDR
  iItem.l
  iSubItem.l
EndStructure

Global NewList Servers.Server()
Global CurServer.i = -1
Global NewList Tor.Torrent()

Global gMutex    = CreateMutex()
Global gRpcMutex = CreateMutex()
Global gThread.i, gQuit.i, gRefresh.i
Global gURL.s, gUser.s, gPass.s, gNoSSL.i
Global gDetTab.i, gDetHash.s
Global gListXml.s, gDetXml.s, gResTab.i, gResHash.s

Global gShownErr.s
Global gInstMutex.i
Global gShowMsg.i = RegisterWindowMessage_("rTorrentRemote_ShowWindow")
Global gWinX.i, gWinY.i, gWinW.i, gWinH.i, gWinMax.i, gWinValid.i
Global gSrvTime.q, gSrvTimeNew.q
Global Dim gColVisible.i(11)
Global Dim gColWidth.i(11)
Global Dim gColName.s(11)
Global gFilter.i = 0
Global gSidebar.i = 1
Global gSortCol.i = -1, gSortDesc.i = 0, gSortReq.i
Global Dim gShown.s(0)
Global Dim gShownRow.s(0)
Global Dim gShownProg.d(0)
Global gOldHdr.i
Global gShownN.i = 0
Global Dim gFilterName.s(7)
Global Dim gFilterTxt.s(7)

;------------------------------------------------------------------------------
; Hjaelpefunktioner
;------------------------------------------------------------------------------
Procedure.s FmtSize(b.q)
  Protected d.d = b
  If d < 1024
    ProcedureReturn Str(b) + " B"
  ElseIf d < 1048576
    ProcedureReturn StrD(d / 1024, 1) + " KiB"
  ElseIf d < 1073741824
    ProcedureReturn StrD(d / 1048576, 1) + " MiB"
  ElseIf d < 1099511627776.0
    ProcedureReturn StrD(d / 1073741824, 2) + " GiB"
  EndIf
  ProcedureReturn StrD(d / 1099511627776.0, 2) + " TiB"
EndProcedure

Procedure.s FmtSpeed(b.q)
  If b <= 0 : ProcedureReturn "" : EndIf
  ProcedureReturn FmtSize(b) + "/s"
EndProcedure

Procedure.s FmtEta(s.q)
  Protected d.q, h.q, m.q
  If s < 0 : ProcedureReturn Chr(8734) : EndIf
  d = s / 86400
  h = (s % 86400) / 3600
  m = (s % 3600) / 60
  If d > 0
    ProcedureReturn Str(d) + "d " + Str(h) + "t"
  ElseIf h > 0
    ProcedureReturn Str(h) + "t " + Str(m) + "m"
  ElseIf m > 0
    ProcedureReturn Str(m) + "m " + Str(s % 60) + "s"
  EndIf
  ProcedureReturn Str(s) + "s"
EndProcedure

Procedure.s ProgText(p.d)
  ProcedureReturn StrD(p, 1) + " %"
EndProcedure

Procedure.s B64(*mem, size.i)
  Protected r.s
  If *mem = 0 Or size <= 0 : ProcedureReturn "" : EndIf
  r = Base64Encoder(*mem, size)
  r = RemoveString(r, #CR$)
  r = RemoveString(r, #LF$)
  ProcedureReturn r
EndProcedure

Procedure.s BasicAuth(user.s, pass.s)
  Protected s.s = user + ":" + pass
  Protected len.i = StringByteLength(s, #PB_UTF8)
  Protected *b = AllocateMemory(len + 2)
  Protected r.s
  PokeS(*b, s, -1, #PB_UTF8)
  r = B64(*b, len)
  FreeMemory(*b)
  ProcedureReturn "Basic " + r
EndProcedure

; Simpel (ikke-kryptografisk) tilsloering af adgangskoden i ini-filen
Procedure.s ObfEnc(s.s)
  Protected i.i, r.s
  For i = 1 To Len(s)
    r + RSet(Hex(Asc(Mid(s, i, 1))), 4, "0")
  Next
  ProcedureReturn r
EndProcedure

Procedure.s ObfDec(h.s)
  Protected i.i, r.s
  For i = 1 To Len(h) Step 4
    r + Chr(Val("$" + Mid(h, i, 4)))
  Next
  ProcedureReturn r
EndProcedure

Procedure.s NormalizeUrl(u.s)
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

Procedure.s RpcCall(url.s, user.s, pass.s, noSSL.i, body.s)
  Protected NewMap hdr.s()
  Protected req.i, flags.i, resp.s, code.s
  hdr("Authorization") = BasicAuth(user, pass)
  hdr("Content-Type")  = "text/xml"
  If noSSL : flags = #PB_HTTP_NoSSLCheck : EndIf
  LockMutex(gRpcMutex)
  req = HTTPRequest(#PB_HTTP_Post, url, body, flags, hdr())
  If req
    code = HTTPInfo(req, #PB_HTTP_StatusCode)
    resp = HTTPInfo(req, #PB_HTTP_Response)
    FinishHTTP(req)
    If code <> "200"
      If code = "401"
        resp = "ERR:HTTP 401 - forkert brugernavn/adgangskode"
      Else
        resp = "ERR:HTTP " + code + " - tjek URL (normalt .../RPC2)"
      EndIf
    EndIf
  Else
    resp = "ERR:Kunne ikke forbinde til serveren"
  EndIf
  UnlockMutex(gRpcMutex)
  ProcedureReturn resp
EndProcedure

Procedure.s CurCall(xml.s)
  ProcedureReturn RpcCall(gURL, gUser, gPass, gNoSSL, xml)
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

Procedure.s ResultError(r.s)
  Protected NewList L.s()
  If Left(r, 4) = "ERR:" : ProcedureReturn Mid(r, 5) : EndIf
  If FindString(r, "<fault>")
    ParseLeaves(r, L())
    If LastElement(L()) : ProcedureReturn L() : EndIf
    ProcedureReturn "Ukendt XML-RPC-fejl"
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.s ListCall()
  Protected f.s = "d.hash=,d.name=,d.size_bytes=,d.completed_bytes=,d.down.rate=,d.up.rate=,d.ratio=,d.state=,d.complete=,d.is_active=,d.peers_complete=,d.peers_accounted=,d.custom1=,d.message=,d.hashing=,d.left_bytes=,d.up.total=,d.down.total=,d.directory=,d.timestamp.finished="
  Protected p.s = PS("") + PS("main")
  Protected i.i
  For i = 1 To #NF_LIST
    p + PS(StringField(f, i, ","))
  Next
  ProcedureReturn MakeXml("d.multicall2", p)
EndProcedure

Procedure.s DetailCall(tab.i, hash.s)
  Select tab
    Case 1
      ProcedureReturn MakeXml("t.multicall", PS(hash) + PS("") + PS("t.url=") + PS("t.is_enabled=") + PS("t.scrape_complete=") + PS("t.scrape_incomplete=") + PS("t.scrape_downloaded="))
    Case 2
      ProcedureReturn MakeXml("p.multicall", PS(hash) + PS("") + PS("p.address=") + PS("p.port=") + PS("p.client_version=") + PS("p.completed_percent=") + PS("p.down_rate=") + PS("p.up_rate="))
    Case 3
      ProcedureReturn MakeXml("f.multicall", PS(hash) + PS("") + PS("f.path=") + PS("f.size_bytes=") + PS("f.completed_chunks=") + PS("f.size_chunks=") + PS("f.priority="))
  EndSelect
  ProcedureReturn ""
EndProcedure

; Sender flere kommandoer pr. torrent i ét kald (system.multicall)
Procedure.s MultiCall(methods.s, List hashes.s())
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
  ProcedureReturn CurCall(MakeXml("system.multicall", x))
EndProcedure

Procedure.s LoadCall(method.s, payload.s, dir.s)
  Protected p.s = PS("") + payload
  If dir <> ""
    p + PS("d.directory.set=" + Chr(34) + dir + Chr(34))
  EndIf
  ProcedureReturn CurCall(MakeXml(method, p))
EndProcedure

;------------------------------------------------------------------------------
; Torrent-data
;------------------------------------------------------------------------------
Procedure ComputeTorrent(*t.Torrent)
  If *t\size > 0
    *t\progress = *t\done * 100.0 / *t\size
  Else
    *t\progress = 0
  EndIf
  If *t\complete : *t\progress = 100 : EndIf
  If *t\leftB > 0 And *t\downRate > 0
    *t\eta = *t\leftB / *t\downRate
  Else
    *t\eta = -1
  EndIf
  If *t\hashing
    *t\status = "Tjekker"
  ElseIf *t\state = 0
    If *t\complete : *t\status = "Færdig" : Else : *t\status = "Stoppet" : EndIf
  ElseIf *t\active = 0
    *t\status = "Pause"
  ElseIf *t\complete
    *t\status = "Seeder"
  Else
    *t\status = "Henter"
  EndIf
  *t\seedSecs = 0
  If *t\complete And *t\finished > 0 And gSrvTime > *t\finished
    *t\seedSecs = gSrvTime - *t\finished
  EndIf
EndProcedure

Procedure ParseTorrents(xml.s)
  Protected NewList L.s()
  Protected Dim f.s(#NF_LIST - 1)
  Protected idx.i = 0
  ParseLeaves(xml, L())
  ClearList(Tor())
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = #NF_LIST
      idx = 0
      AddElement(Tor())
      Tor()\hash      = f(0)
      Tor()\name      = f(1)
      Tor()\size      = Val(f(2))
      Tor()\done      = Val(f(3))
      Tor()\downRate  = Val(f(4))
      Tor()\upRate    = Val(f(5))
      Tor()\ratio     = Val(f(6))
      Tor()\state     = Val(f(7))
      Tor()\complete  = Val(f(8))
      Tor()\active    = Val(f(9))
      Tor()\seeds     = Val(f(10))
      Tor()\peers     = Val(f(11))
      Tor()\lbl       = URLDecoder(f(12))
      Tor()\message   = f(13)
      Tor()\hashing   = Val(f(14))
      Tor()\leftB     = Val(f(15))
      Tor()\upTotal   = Val(f(16))
      Tor()\downTotal = Val(f(17))
      Tor()\dir       = f(18)
      Tor()\finished  = Val(f(19))
      ComputeTorrent(@Tor())
    EndIf
  Next
EndProcedure

Procedure SortTorrents()
  Protected fl.i = #PB_Sort_Ascending
  If gSortCol < 0 : ProcedureReturn : EndIf
  If gSortDesc : fl = #PB_Sort_Descending : EndIf
  Select gSortCol
    Case 0  : SortStructuredList(Tor(), fl | #PB_Sort_NoCase, OffsetOf(Torrent\name), #PB_String)
    Case 1  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\size), #PB_Quad)
    Case 2  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\progress), #PB_Double)
    Case 3  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\status), #PB_String)
    Case 4  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\seeds), #PB_Long)
    Case 5  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\peers), #PB_Long)
    Case 6  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\downRate), #PB_Quad)
    Case 7  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\upRate), #PB_Quad)
    Case 8  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\eta), #PB_Quad)
    Case 9  : SortStructuredList(Tor(), fl, OffsetOf(Torrent\seedSecs), #PB_Quad)
    Case 10 : SortStructuredList(Tor(), fl, OffsetOf(Torrent\ratio), #PB_Quad)
    Case 11 : SortStructuredList(Tor(), fl | #PB_Sort_NoCase, OffsetOf(Torrent\lbl), #PB_String)
  EndSelect
EndProcedure

Procedure.i Matches(*t.Torrent, f.i)
  Select f
    Case 0 : ProcedureReturn #True
    Case 1 : ProcedureReturn Bool(*t\status = "Henter")
    Case 2 : ProcedureReturn Bool(*t\status = "Seeder")
    Case 3 : ProcedureReturn Bool(*t\complete <> 0)
    Case 4 : ProcedureReturn Bool(*t\state = 0 Or *t\active = 0)
    Case 5 : ProcedureReturn Bool(*t\downRate > 0 Or *t\upRate > 0)
    Case 6 : ProcedureReturn Bool(*t\downRate = 0 And *t\upRate = 0)
    Case 7 : ProcedureReturn Bool(*t\message <> "")
  EndSelect
  ProcedureReturn #False
EndProcedure

Procedure.s RowText(*t.Torrent)
  Protected e.s = "", sd.s = ""
  If *t\complete = 0 : e = FmtEta(*t\eta) : EndIf
  If *t\seedSecs > 0 : sd = FmtEta(*t\seedSecs) : EndIf
  ProcedureReturn *t\name + #LF$ + FmtSize(*t\size) + #LF$ + ProgText(*t\progress) + #LF$ + *t\status + #LF$ + Str(*t\seeds) + #LF$ + Str(*t\peers) + #LF$ + FmtSpeed(*t\downRate) + #LF$ + FmtSpeed(*t\upRate) + #LF$ + e + #LF$ + sd + #LF$ + StrD(*t\ratio / 1000.0, 2) + #LF$ + *t\lbl
EndProcedure

;------------------------------------------------------------------------------
; GUI-opdatering
;------------------------------------------------------------------------------
Procedure GetSelectedHashes(List out.s())
  Protected i.i
  ClearList(out())
  For i = 0 To CountGadgetItems(#G_List) - 1
    If GetGadgetItemState(#G_List, i) & #PB_ListIcon_Selected
      If i < gShownN
        AddElement(out())
        out() = gShown(i)
      EndIf
    EndIf
  Next
EndProcedure

Procedure RefreshList()
  Protected NewList hashes.s()
  Protected NewList rows.s()
  Protected NewList sel.s()
  Protected NewList progs.d()
  Protected Dim cnt.i(7)
  Protected i.i, c.i, f.i, n.i, ok.i, same.i, q.s, t.s
  q = LCase(Trim(GetGadgetText(#G_Search)))

  ForEach Tor()
    For f = 0 To 7
      If Matches(@Tor(), f) : cnt(f) + 1 : EndIf
    Next
    ok = Matches(@Tor(), gFilter)
    If ok And q <> ""
      If FindString(LCase(Tor()\name), q) = 0 : ok = #False : EndIf
    EndIf
    If ok
      AddElement(hashes()) : hashes() = Tor()\hash
      AddElement(rows())   : rows()   = RowText(@Tor())
      AddElement(progs())  : progs()  = Tor()\progress
    EndIf
  Next

  ; sidebjælke-tal
  For f = 0 To 7
    t = gFilterName(f) + " (" + Str(cnt(f)) + ")"
    If t <> gFilterTxt(f)
      gFilterTxt(f) = t
      SetGadgetItemText(#G_Filter, f, t)
    EndIf
  Next
  If GetGadgetState(#G_Filter) <> gFilter : SetGadgetState(#G_Filter, gFilter) : EndIf

  n = ListSize(hashes())
  same = Bool(n = gShownN And n = CountGadgetItems(#G_List))
  If same
    i = 0
    ForEach hashes()
      If hashes() <> gShown(i) : same = #False : Break : EndIf
      i + 1
    Next
  EndIf

  If same
    i = 0
    ForEach rows()
      If rows() <> gShownRow(i)
        For c = 0 To 11
          SetGadgetItemText(#G_List, i, StringField(rows(), c + 1, #LF$), c)
        Next
        gShownRow(i) = rows()
        If SelectElement(progs(), i) : gShownProg(i) = progs() : EndIf
      EndIf
      i + 1
    Next
  Else
    GetSelectedHashes(sel())
    ClearGadgetItems(#G_List)
    Dim gShown(n)
    Dim gShownRow(n)
    Dim gShownProg(n)
    gShownN = n
    i = 0
    ForEach hashes()
      gShown(i) = hashes()
      i + 1
    Next
    i = 0
    ForEach progs()
      gShownProg(i) = progs()
      i + 1
    Next
    i = 0
    ForEach rows()
      gShownRow(i) = rows()
      AddGadgetItem(#G_List, -1, rows())
      ForEach sel()
        If sel() = gShown(i)
          SetGadgetItemState(#G_List, i, #PB_ListIcon_Selected)
          Break
        EndIf
      Next
      i + 1
    Next
  EndIf
EndProcedure

Procedure UpdateGeneral()
  Protected i.i, found.i = #False, v.s
  If gDetHash <> ""
    ForEach Tor()
      If Tor()\hash = gDetHash : found = #True : Break : EndIf
    Next
  EndIf
  For i = 0 To 14
    v = ""
    If found
      Select i
        Case 0  : v = Tor()\name
        Case 1  : v = Tor()\hash
        Case 2  : v = Tor()\dir
        Case 3  : v = FmtSize(Tor()\size)
        Case 4  : v = FmtSize(Tor()\done)
        Case 5  : v = StrD(Tor()\progress, 1) + " %"
        Case 6  : v = Tor()\status
        Case 7  : v = Str(Tor()\seeds)
        Case 8  : v = Str(Tor()\peers)
        Case 9  : v = StrD(Tor()\ratio / 1000.0, 2)
        Case 10 : v = FmtSize(Tor()\upTotal)
        Case 11 : v = FmtSize(Tor()\downTotal)
        Case 12 : v = Tor()\lbl
        Case 13 : v = Tor()\message
        Case 14 : If Tor()\seedSecs > 0 : v = FmtEta(Tor()\seedSecs) : EndIf
      EndSelect
    EndIf
    SetGadgetItemText(#G_General, i, v, 1)
  Next
EndProcedure

Procedure FillDetail(gad.i, det.s)
  Protected NewList L.s()
  Protected Dim f.s(7)
  Protected nf.i, idx.i = 0, txt.s, tot.q, pct.d, pr.s
  Select gad
    Case #G_Trackers : nf = 5
    Case #G_Peers    : nf = 6
    Case #G_Files    : nf = 5
    Default          : ProcedureReturn
  EndSelect
  ParseLeaves(det, L())
  ClearGadgetItems(gad)
  ForEach L()
    f(idx) = L()
    idx + 1
    If idx = nf
      idx = 0
      Select gad
        Case #G_Trackers
          If f(1) = "1" : pr = "Aktiv" : Else : pr = "Deaktiveret" : EndIf
          txt = f(0) + #LF$ + pr + #LF$ + f(2) + #LF$ + f(3) + #LF$ + f(4)
        Case #G_Peers
          txt = f(0) + #LF$ + f(1) + #LF$ + f(2) + #LF$ + f(3) + " %" + #LF$ + FmtSpeed(Val(f(4))) + #LF$ + FmtSpeed(Val(f(5)))
        Case #G_Files
          tot = Val(f(3))
          pct = 0
          If tot > 0 : pct = Val(f(2)) * 100.0 / tot : EndIf
          Select Val(f(4))
            Case 0 : pr = "Spring over"
            Case 2 : pr = "Høj"
            Default : pr = "Normal"
          EndSelect
          txt = f(0) + #LF$ + FmtSize(Val(f(1))) + #LF$ + ProgText(pct) + #LF$ + pr
      EndSelect
      AddGadgetItem(gad, -1, txt)
    EndIf
  Next
EndProcedure

Procedure UpdateDetails(det.s, tab.i, hash.s)
  If tab <> gDetTab Or hash <> gDetHash : ProcedureReturn : EndIf
  If det = "" Or ResultError(det) <> "" : ProcedureReturn : EndIf
  Select tab
    Case 1 : FillDetail(#G_Trackers, det)
    Case 2 : FillDetail(#G_Peers, det)
    Case 3 : FillDetail(#G_Files, det)
  EndSelect
EndProcedure

Procedure OnSelection()
  Protected NewList sel.s()
  Protected h.s = ""
  GetSelectedHashes(sel())
  If FirstElement(sel()) : h = sel() : EndIf
  If h <> gDetHash
    LockMutex(gMutex)
    gDetHash = h
    UnlockMutex(gMutex)
    ClearGadgetItems(#G_Trackers)
    ClearGadgetItems(#G_Peers)
    ClearGadgetItems(#G_Files)
    gRefresh = 1
  EndIf
  UpdateGeneral()
EndProcedure

Procedure OnPoll()
  Protected xml.s, det.s, tab.i, hash.s, e.s
  Protected dl.q, ul.q, srv.s = ""
  LockMutex(gMutex)
  xml = gListXml : det = gDetXml : tab = gResTab : hash = gResHash : gSrvTime = gSrvTimeNew
  UnlockMutex(gMutex)
  If xml = "" : ProcedureReturn : EndIf
  If CurServer >= 0 And SelectElement(Servers(), CurServer) : srv = Servers()\name : EndIf

  e = ResultError(xml)
  If e <> ""
    StatusBarText(0, 0, "Fejl: " + e)
    If e <> gShownErr
      gShownErr = e
      MessageRequester(#APP_NAME, "Kunne ikke hente listen:" + #LF$ + e + #LF$ + #LF$ + "Brug Server > Test forbindelse for flere detaljer.", #PB_MessageRequester_Error)
    EndIf
    ProcedureReturn
  EndIf
  gShownErr = ""

  ParseTorrents(xml)
  SortTorrents()
  RefreshList()
  OnSelection()
  UpdateDetails(det, tab, hash)

  ForEach Tor()
    dl + Tor()\downRate
    ul + Tor()\upRate
  Next
  StatusBarText(0, 0, "Forbundet: " + srv)
  StatusBarText(0, 1, Chr(8595) + " " + FmtSize(dl) + "/s")
  StatusBarText(0, 2, Chr(8593) + " " + FmtSize(ul) + "/s")
  StatusBarText(0, 3, Str(ListSize(Tor())) + " torrents")
EndProcedure

Procedure OnSort()
  If gSortReq = gSortCol
    gSortDesc = 1 - gSortDesc
  Else
    gSortCol = gSortReq
    gSortDesc = 0
  EndIf
  SortTorrents()
  RefreshList()
EndProcedure

;------------------------------------------------------------------------------
; Baggrundstraad der poller serveren
;------------------------------------------------------------------------------
Procedure PollThread(dummy.i)
  Protected url.s, user.s, pass.s, noSSL.i, tab.i, hash.s
  Protected resp.s, det.s, i.i, tm.s, srvT.q
  Protected NewList tl.s()
  While gQuit = 0
    LockMutex(gMutex)
    url = gURL : user = gUser : pass = gPass : noSSL = gNoSSL
    tab = gDetTab : hash = gDetHash
    UnlockMutex(gMutex)
    gRefresh = 0

    If url <> ""
      resp = RpcCall(url, user, pass, noSSL, ListCall())
      det = ""
      If tab > 0 And hash <> "" And Left(resp, 4) <> "ERR:"
        det = RpcCall(url, user, pass, noSSL, DetailCall(tab, hash))
      EndIf
      srvT = 0
      If Left(resp, 4) <> "ERR:"
        tm = RpcCall(url, user, pass, noSSL, MakeXml("system.time", ""))
        ParseLeaves(tm, tl())
        If FirstElement(tl()) : srvT = Val(tl()) : EndIf
      EndIf
      LockMutex(gMutex)
      If url = gURL
        gListXml = resp : gDetXml = det : gResTab = tab : gResHash = hash : gSrvTimeNew = srvT
      EndIf
      UnlockMutex(gMutex)
      PostEvent(#EvPoll, #Win, 0)
    EndIf

    For i = 1 To 30
      If gQuit Or gRefresh : Break : EndIf
      Delay(100)
    Next
  Wend
EndProcedure

;------------------------------------------------------------------------------
; Server-opsaetning
;------------------------------------------------------------------------------
; Husker vinduets normale position/stoerrelse (ogsaa naar det er maksimeret)
Procedure CaptureWindow()
  If IsWindow(#Win) = 0 : ProcedureReturn : EndIf
  Select GetWindowState(#Win)
    Case #PB_Window_Normal
      gWinX = WindowX(#Win)
      gWinY = WindowY(#Win)
      gWinW = WindowWidth(#Win)
      gWinH = WindowHeight(#Win)
      gWinMax = 0
      gWinValid = 1
    Case #PB_Window_Maximize
      gWinMax = 1
  EndSelect
EndProcedure

; Er punktet paa en af de tilsluttede skaerme?
Procedure.i OnAnyDesktop(x.i, y.i)
  Protected i.i, n.i, ok.i = #False
  n = ExamineDesktops()
  For i = 0 To n - 1
    If x >= DesktopX(i) And x < DesktopX(i) + DesktopWidth(i) And y >= DesktopY(i) And y < DesktopY(i) + DesktopHeight(i)
      ok = #True
    EndIf
  Next
  ProcedureReturn ok
EndProcedure

Procedure CaptureColumns()
  Protected c.i, w.i
  If IsGadget(#G_List) = 0 : ProcedureReturn : EndIf
  For c = 1 To 11
    If gColVisible(c)
      w = GetGadgetItemAttribute(#G_List, 0, #PB_ListIcon_ColumnWidth, c)
      If w > 0 : gColWidth(c) = w : EndIf
    EndIf
  Next
EndProcedure

Procedure LoadServers()
  Protected n.i, i.i, c.i
  ClearList(Servers())
  CurServer = 0
  If OpenPreferences(GetEnvironmentVariable("APPDATA") + "\rTorrentRemote\servers.ini")
    PreferenceGroup("General")
    n = ReadPreferenceInteger("Count", 0)
    CurServer = ReadPreferenceInteger("Selected", 0)
    For i = 0 To n - 1
      PreferenceGroup("Server" + Str(i))
      AddElement(Servers())
      Servers()\name  = ReadPreferenceString("Name", "")
      Servers()\url   = ReadPreferenceString("Url", "")
      Servers()\user  = ReadPreferenceString("User", "")
      Servers()\pass  = ObfDec(ReadPreferenceString("Pass", ""))
      Servers()\noSSL = ReadPreferenceInteger("NoSSL", 0)
    Next
    PreferenceGroup("Columns")
    For c = 1 To 11
      gColVisible(c) = ReadPreferenceInteger("Vis" + Str(c), 1)
      gColWidth(c) = ReadPreferenceInteger("W" + Str(c), gColWidth(c))
    Next
    PreferenceGroup("Window")
    gWinX   = ReadPreferenceInteger("X", 0)
    gWinY   = ReadPreferenceInteger("Y", 0)
    gWinW   = ReadPreferenceInteger("W", 0)
    gWinH   = ReadPreferenceInteger("H", 0)
    gWinMax = ReadPreferenceInteger("Max", 0)
    PreferenceGroup("View")
    gSidebar = ReadPreferenceInteger("Sidebar", 1)
    If gWinW >= 900 And gWinH >= 520 : gWinValid = 1 : Else : gWinValid = 0 : EndIf
    ClosePreferences()
  EndIf
  If CurServer >= ListSize(Servers()) : CurServer = ListSize(Servers()) - 1 : EndIf
  If CurServer < 0 And ListSize(Servers()) > 0 : CurServer = 0 : EndIf
EndProcedure

Procedure SaveServers()
  Protected i.i = 0, c.i, dir.s = GetEnvironmentVariable("APPDATA") + "\rTorrentRemote\"
  CaptureWindow()
  CaptureColumns()
  CreateDirectory(dir)
  If CreatePreferences(dir + "servers.ini")
    PreferenceGroup("General")
    WritePreferenceInteger("Count", ListSize(Servers()))
    WritePreferenceInteger("Selected", CurServer)
    ForEach Servers()
      PreferenceGroup("Server" + Str(i))
      WritePreferenceString("Name", Servers()\name)
      WritePreferenceString("Url", Servers()\url)
      WritePreferenceString("User", Servers()\user)
      WritePreferenceString("Pass", ObfEnc(Servers()\pass))
      WritePreferenceInteger("NoSSL", Servers()\noSSL)
      i + 1
    Next
    PreferenceGroup("Columns")
    For c = 1 To 11
      WritePreferenceInteger("Vis" + Str(c), gColVisible(c))
      WritePreferenceInteger("W" + Str(c), gColWidth(c))
    Next
    If gWinValid
      PreferenceGroup("Window")
      WritePreferenceInteger("X", gWinX)
      WritePreferenceInteger("Y", gWinY)
      WritePreferenceInteger("W", gWinW)
      WritePreferenceInteger("H", gWinH)
      WritePreferenceInteger("Max", gWinMax)
    EndIf
    PreferenceGroup("View")
    WritePreferenceInteger("Sidebar", gSidebar)
    ClosePreferences()
  EndIf
EndProcedure

Procedure FillServerCombo()
  ClearGadgetItems(#G_Server)
  ForEach Servers()
    AddGadgetItem(#G_Server, -1, Servers()\name)
  Next
  If CurServer >= 0 : SetGadgetState(#G_Server, CurServer) : EndIf
EndProcedure

; ---------------------------------------------------------------
; Programikon (ruTorrent-stil), indlejret som PNG-data i hex
; ---------------------------------------------------------------
Global gIconSm.i, gIconBig.i

Procedure.i IconFromHex(hex.s, size.i)
  Protected n.i = Len(hex) / 2, i.i, *m, h.i
  *m = AllocateMemory(n)
  If *m = 0 : ProcedureReturn 0 : EndIf
  For i = 0 To n - 1
    PokeA(*m + i, Val("$" + Mid(hex, i * 2 + 1, 2)))
  Next
  h = CreateIconFromResourceEx_(*m, n, #True, $30000, size, size, 0)
  FreeMemory(*m)
  ProcedureReturn h
EndProcedure

Procedure ApplyIcon(hwnd.i)
  Protected h16.s, h48.s
  If gIconSm = 0
    h16 = "89504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff610000031b4944415478da5593dd8b556518c5d7fbb1f7"
    h16 + "3ec73395d310811f547824c2b10f88a90894b241cc6a72e058e945d05f20116150825d15816077417f40cc40515122324d624de1cca817"
    h16 + "1e469973cc726810bfced9e763effdbeeff33c5d1c455b578bc55a370b7e0ab755ab89999e560400fb261b2f8ad038e0368b1088d4b273"
    h16 + "d9ccf7c79f3f35e84e99e9e9bd0400eadee0ed37eacf942b95cf94f6afc451a445082c0466429e77c5799ee9a7ad833fcdee5cbcb35177"
    h16 + "ccbe37eb1395a1fbbe29576c29d02d0831b110443184094c410325d5edf45c2b6dbd737cf6b56f6bb529a300a8daaea5d1a1b5c9c29a0a"
    h16 + "c7599e8522f3d658010bc1151e2204a5194982a094b2edb6f3ad7677ece4dc9e73161030ea4793248ab3ec5678e4d1c46e797218cb17db"
    h16 + "c873c2a6ea089412ac5ce9a07efe86cd731f4a4929622abe0464bbdab96df18552399e1b7e50b828bc7e6bffc398985c0fef09516470af"
    h16 + "2e355b38f2c5229acb2977d242a7edce362b905d2168f4bb7d61105c4120124491c19f739771eeec35680d6caa0e63c778159f1c1e436d"
    h16 + "e23b295c046879d53285cd1e0e69a780f71e4511608cc2c2fc157c7a6801715c419af6117c03f5f3d7502e0b9c2b501404e650b5241e60"
    h16 + "83101cdaad0cdd9e0300341b298adc02f078f7bd2770f56a8aa347ce426b4692682805107b6861df600e200e70dec3bb00001066acaeb6"
    h16 + "d1efe7d8fdfa63d831be0ee535c0d050049100e60061d7d414e458085d8804c5ecc132f88088d1e96458b73ec6036b636cd8783f464680"
    h16 + "5e2f830829a20c2cf4b33eb5f0f21f21e427b54ab40f2e580b18a3602c10c782f9d3abf8f0fd63f8e0c00f68363ab0110716ad43287e5f"
    h16 + "be9cffa60060ece91f9f324ae6f3228f366cd461cbd68abdb0741d1796ba48128d76bb07a51849490722b2221244dc73cd7f3e3e636ab5"
    h16 + "2973e297c9d5874676d76d64f7dcb84ed199c57fe5e64dc7510409c14b9c408c61c56c8c70f044f9fe4b2b8766809af91f4ca38f7ffd6c"
    h16 + "64a3cf81f012b3522138c86d98887308f32c7176f0af95c3a7812903ec257517e7bb888e56bfdacea071e66280b37043844e34fffee8d7"
    h16 + "417b300680ff00f1d7f9a46e333dfe0000000049454e44ae426082"
    h48 = "89504e470d0a1a0a0000000d49484452000000300000003008060000005702f98700000e7c4944415478dab55a7b8c1de575ff9def9b99"
    h48 + "7bef7a1fb6d736c636a90da68d4c4c710d8140958b05058734d0062d12a6818a448ada888a475a4109bdbeff586da9a2a655f340242d4a"
    h48 + "629adda4718363412c6cdf408465f02b7ed486d83c6c5363f063bdde9d3b33df39a77fccdc7b67f6e1b63c461acdded9799cc7effccee3"
    h48 + "1be0036c030383b65addec9dff2aa5a9fe53ad6ef6060606ed079181de9fe06a878620002900dc537dbd1ccf90cb05bc5c8597026ea1aa"
    h48 + "f62bb40bca4430a3a2720ac09b0add2b0edb9dafbbd7afbf722c6f8ca1a13bf82355a05653b3ba0ea54cf03bffe87095485681e4264366"
    h48 + "a1e7974150281c5419aa0255c95e93ee228ac48560171f51c5461659fb9fcf5efd7ccb5bb51aa85e27f9d01548ad4e0c007ff2f943b7c3"
    h48 + "d003c6d075be178025846aa4203041015252550214508542004045545515226c019f884a489208ece26dc2fc8feb9ebbeee9f1effa1014"
    h48 + "e85865d56d07aff0fce071cf0f6e24c3603ea7c61083d410c1102980ceaeaae913322554d3732a0a1111511566310625c3424892b01137"
    h48 + "c3bffaf9a61bb7d56a3553afafd6164cdf970235d44c1d750180bb3e7fe841cfb36bfcc02fb18c3091923564408a8ee040c7ea9912f9df"
    h48 + "2d055421aa29c444e198455894a862a33876ce25b5679ebb7e4d26854126c3ff4b815a4d4dbd4eb272e586d2ac69bff3bd4aa567959333"
    h48 + "3046d818b2865ac6c9093e5ed89c12a937b2634b91ecb7884044c18e99590d51378d85c33f8df4d817366ebc7b34f5c6e44a4ca140aaf5"
    h48 + "4075737769f6453febaaf4ad48f85462ad7ad61011753c9be25b333d7202a6b89f28fc3825a5f5770a2b3866754e1ca1db1f0b475e3a17"
    h48 + "8fdcd268fcf199a93c4153617eff7e78811c7ab6abd2b3c2c9e9c4f3c8370605b82804c870de114a5ac0c9092dd965937828e789963798"
    h48 + "0549c209b4cb1f1b1bd9eaec891bafdd7828ac63624c9889c9658badd7496c7ce0a972b97745c2a713cf926f4841246dd81485972c48c7"
    h48 + "0b2f1385d74cc93c8c32a8111444803180e7912f3a9294cbddd7209ebeb68eba54ab5bec78a3dbf154b961c322befd0ff73e306ddaac87"
    h48 + "584e27be07df58c0980ed65b96c324f0d0b6421d1642db0bad6b918b0f69c3afb803aa6a9d0b13cff62e993ff773b2e5855bb60c0c0cda"
    h48 + "fdfb877402845a417bfbcdaf5de697cd0e3f70d6f3d8783e510a1d145e68cc388800900cc7adf3840ee43a704196e014a2528c9d1cd58a"
    h48 + "2ad809e2d8691c0b47118c6b36af6ebc3cf04a3e6b4fa863c444ff626d4fa0d26422437986c95bf4dc888348069dec9a72d9c0663e2502"
    h48 + "5c22481286730c914c2952500a11f83ec1188025173b6ddba6703706040859e39b88e49b40ed9a254b068a1e6865becfddbcefb64ad0bd"
    h48 + "8ee82c072563fd00b0b663ed96f0a28265cb7bd0dd6352a5086027d8b9e31486cf0892584010f4cdf030674e8099b3024c9be6c158200c"
    h48 + "1dce9c8e70e2788877df0d3136c6280516a5b24d0d92831fb3c0258c28628461c2cc651b8523776ddd75e7da6ab5e6351a75e701c09225"
    h48 + "ab155002fffa5191448dc9309aa778020c29ce8d26b8e6ba3efcd95f2c9ac05f8b3679f8d63f1fc41fdcb408bf77d50c5c72690ffafa82"
    h48 + "49893a8e19c78e9cc3ce1d27f0e20bff8dc3bf1941b91c2028119ccb622c974b0040245691e4afabd5da60a3b19a813aa865fd95d55dbf"
    h48 + "1f942a2f10851204648280e00704cf030ca1e54e9c1d8e70cbadb370e71716829dc07a04d51432674e87084387f90b7a8bb0142d188288"
    h48 + "b2984a37e7188d4d47b0f6870770f23d879e9e1292c4415891248c287268361d9acd58440293c4e756eed877ef73d56acd33274e6ca10c"
    h48 + "4c771bf2a1aa9206632b430a442517ac0ae704c600d6128ca1f671667f17e62fe845ebfe169e8d49ff6fb2eb8832038b8259e1791637dc"
    h48 + "b4108f7ffdd3b86c6937864f9f8331d479bf0844182a2aaaa40adc030073e65c96361bd5eae672997a5ff36c69011089ef930902c00fd2"
    h48 + "40b3366513eb11868723acbca51ff77cf112082b8ced98b2c5f744942525cd02ba6571ca58a6739dc9788259612d218e1d1e7b6413f6ee"
    h48 + "1941a51c206c26889a0e51e410c74e99899c8bdf6b0a2e3e78f04b2306002adab7d452698173a1aaa8611638d7d999d35a45a555df4f5e"
    h48 + "2052060f9154386b0dac3599d5294b52a9c75ae75bb4692d415811041ebefaf0b528976384610c7602e718cc0c6121e6588882591e92e5"
    h48 + "6d1a65c8551e95e0648c19ea813bc2b42c97b211412547a7536cc610ce9e0db1e395b770e0bfdec1f1e323183d1783455129fb98d15fc1"
    h48 + "a28b67e28a2b16e092c5733af75902b360f6ec6e7ce6b38bf0e413fbd0dbd303e73835640a27b1c692517c12c0160f0048b0b455af4315"
    h48 + "ccc572293b0d32062c922b1630215855153ffdc94e3cfd839d387346604c09be17c0580f0440348173c3707c0441b013575e3917f7ddff"
    h48 + "69ccec9f96e61a015419577fea223cf9c40e349be58e07da250893a82e6d7b4049168a38880a91682eeba6158a28209232914ba4c32ab9"
    h48 + "8d5960adc1be3d6fe3eb7fff22e6cdfb2dcc9fd70d636c66803c2566d9961db66c7a07e5f2363c5abba1f0bc4b7f7b0efc40d00c23a8a6"
    h48 + "019d4198441da0fab18e022afda20e8050fb6559b06926bca45d2192d881b9a8806a0a9be3c787b1fe997db8e08279e8eaea6b3359bef6"
    h48 + "ef34350210306b563f8e1d8df1a3a7772049a2f6bbcf9e8dd00c1dd849268364995f4995a1907e00e4014a8a97ba543887ed56ad0218d1"
    h48 + "9c028266c46027e31450184378e3f59358f79357b168d1623827852eac5da4515a0b892ac4a5de3c7468042f6f7b1d5114c23946e2182a"
    h48 + "4077771f883a94dea9a718aa5259bcf81b415a0b8942ad4c6807a10a46a600a759288a1c9c9bbcc3f33c0fd3ba7be1d842858b4d0c1471"
    h48 + "cc08c3042a0296b43e2a973d8800bd7dfd60c719de058e254d6659b7d6a9640580c964247800a9ea0b6106a5b645dbe52f2948b36c4a40"
    h48 + "1cf1940a88289aa1431cb92c4e3a654014392cb8a80b77dfbb0c36ab6e0f1e780f4f7e6737acf5c02c855d553af0d34e85ab59df00d5f0"
    h48 + "3787ee4fb218d0935992d1098db874da436620c92c54c450abafd176da57e93cc7d8b4cca8ae988beaf50bdab77de2f29978e25bbf421c"
    h48 + "77818852a6116dcf93548bfd461a47a24a04859c02205939ad6fa6e01455420eb79d00842a4800619e9007da91a3a90251cb03596fdcca"
    h48 + "b0cd660c66cd6a288391b34dc449132aa54c818ee079a1db3d762a9742090abcd5662181ec6935d8049df2012ad4ae73269d20a9c2258c"
    h48 + "24e602fb080b464763c431c35a826a9a8d89085194403886e7d9ac469a54e8dcc04032ded3bd9d8646f08ae310809a491f5074e194a504"
    h48 + "14590072e6815489391754c012a35229b6e0c612fafa02585306336178384c6ba3f37841a146242140b7b515884c6977c0636f1be3cd63"
    h48 + "8e045053e0ed361da2d8994d903f6d7634630e438ad1d108d51517e3be076e85739cb155aac8ecd9bd78f6f93fc7a99363b8f79e219c3c"
    h48 + "e910041ea636a228c11896f0141bdd0e00a65addec6ddd7a6d08c82f8802957482394e78c9b973320f6801462de66016542a1e9ef8f676"
    h48 + "fc6cdd5ef4f494da0c26a2b0d6a052f1f0d507ff1daf1e388e52c9b6dbd4c23b3b631726f215aacf1f3efcf0f00006ad9933e75d4d1986"
    h48 + "9f1289a965fd09a392f67cf33c106a27c10efd2914dddd5d78f8a18d58ffcc3e789e4192305ab4fdc53ffd2e1a9bdfc4cc9933d220cee1"
    h48 + "3e6f8c14fb42aa4c503c050027b08f4cdaddd7ccafb66ffda573a3bbac2991aa7071a22605469ab218cdd73c99f0220243849edee978f0"
    h48 + "be0d78f19787e0fb16c6101eba7f2d36ac7f0d175e381fcc346eec38c10b42f08de3b183bdb367fc02506aa0ee4cdad05c6f80ba10740d"
    h48 + "60a84d65adf9fef887b62d8cc2de4af75a980ba559d75a03cf4ec397bff41fd8f3eb6378fc6f7f8e7ffbde76ccbb7001d851812426270f"
    h48 + "56902115fabbeddbbf9c00ab6d7b32d768ac70b59a9a17b77ff6c7893bfb9235159bf7429b7db2d19f1f98ac6149fb85d6b152f1a1edb9"
    h48 + "9074d84415cc0e7ee0c12525dc75c75a7cfb9b2f63eedc05706c7242cb44c653812a335160d98deebee868f4fd6c4eca85d1e2fefd4394"
    h48 + "76eefa159198d3124314b938101104258b5d3b8ee3e4c951c47182384a1045099a618cc6965727cc40f36b03cc8ca0e4c3b912caa59930"
    h48 + "e44f3a7a2f781eaaaaa4aa0c25fe4a037507eca75620d2f845bba1a13bf89357fcf891c09bbe26494e270af8f9ac4c04846188bee9314a"
    h48 + "1597156d0033e3ed6363289767c09a525be8095cae9225ace27cb465fdbce29927136bba7ce746d61c3efa378f028316e8aca58d9f4e53"
    h48 + "b5bad9361a2bdc55bf3bb8ceb7bdb725c97002829f2fa8408a388ee05c5c60a520f033a716695827cc4627e7798c4b96a2925853f1d98d"
    h48 + "6e3c7cf4b19b812103dc51a0c1f1a3456d34ae67a066c42baf4adcc8f3d69b768d4bce264af0db2f1485effbf07daf2094087f00a18bd7"
    h48 + "8b48624dd9676eee42100ca4e2edd3f11c6e26992d28006cdf7eeb588c739f713cf692f5ba7d88249a76f46d6185b9702ce68af1c24f95"
    h48 + "9ca410f059199d5a5ea29d88e39b0f1f7e7818584d932d704cb1c8dc50a066de79e781707a7ff54716de126ba75dc6d284aa08a06612ac"
    h48 + "4e18b7b7b1fd7f878e00506bba3c96f05936c9ad6f1cab9f3cdf3ad9ffb24ad9b971f992ef3fa6443590b5ec46396d6f602658fabc0a4d"
    h48 + "011d4da74e44bea7ca50e135878f7eed6b295cdee7225ff15381d47dcb3efed4a760f00f44feb52209589a9235410650d249163da66618"
    h48 + "515511551091670816a2f1cb2cf15fbe71b4d6e87ca2f001965927a35800b8fce3dfbd9b40f783ccb274f5bd09112769e25040855a0ae5"
    h48 + "2093fe4c3d66888c2178500844e23d10f9a7434777ff2b30c4e3a9f243fc5622efce9af9c4a50b5612c92a55b981c8ce0579d92706dcf9"
    h48 + "d4a0bd84940dc900a82410894f00d8acaa6b0f1d893600759799caa64a7ca41f7b143fcc587ef177fa9a24cbc4f055cab254211f23c84c"
    h48 + "55e9cabc10aae21441df52c25e2378a509d9f1d65b8f9cee3c75d08ee7f88f7aa3010cdaf37d2eb364c960b078f1374a533f62d0a6fbfb"
    h48 + "332400fc0f3e950d7cac9337040000000049454e44ae426082"
    gIconSm  = IconFromHex(h16, 16)
    gIconBig = IconFromHex(h48, 48)
  EndIf
  If gIconSm  : SendMessage_(hwnd, #WM_SETICON, #ICON_SMALL, gIconSm)  : EndIf
  If gIconBig : SendMessage_(hwnd, #WM_SETICON, #ICON_BIG,   gIconBig) : EndIf
EndProcedure

Procedure ApplyServer()
  LockMutex(gMutex)
  If CurServer >= 0 And SelectElement(Servers(), CurServer)
    gURL = Servers()\url : gUser = Servers()\user : gPass = Servers()\pass : gNoSSL = Servers()\noSSL
    SetWindowTitle(#Win, #APP_NAME + " - " + Servers()\name)
    StatusBarText(0, 0, "Forbinder til " + Servers()\name + " ...")
  Else
    gURL = "" : gUser = "" : gPass = "" : gNoSSL = 0
    SetWindowTitle(#Win, #APP_NAME)
    StatusBarText(0, 0, "Ingen server valgt - brug Server > Administrer servere...")
  EndIf
  gListXml = "" : gDetXml = ""
  gDetHash = ""
  UnlockMutex(gMutex)
  ClearList(Tor())
  RefreshList()
  UpdateGeneral()
  gRefresh = 1
EndProcedure

Procedure ServerDialog()
  Protected ev.i, quit.i, sel.i, url.s

  DisableWindow(#Win, #True)
  If OpenWindow(#WinSrv, 0, 0, 650, 300, "Servere", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#Win))
    ApplyIcon(WindowID(#WinSrv))
    ListViewGadget(#G_SrvList, 10, 10, 190, 280)
    TextGadget(#PB_Any, 215, 12, 200, 18, "Navn:")
    StringGadget(#G_SrvName, 215, 30, 420, 24, "")
    TextGadget(#PB_Any, 215, 60, 420, 18, "URL (f.eks. https://bruger.server.usbx.me/RPC2):")
    StringGadget(#G_SrvUrl, 215, 78, 420, 24, "")
    TextGadget(#PB_Any, 215, 108, 200, 18, "Brugernavn:")
    StringGadget(#G_SrvUser, 215, 126, 420, 24, "")
    TextGadget(#PB_Any, 215, 156, 200, 18, "Adgangskode:")
    StringGadget(#G_SrvPass, 215, 174, 420, 24, "", #PB_String_Password)
    CheckBoxGadget(#G_SrvNoSSL, 215, 206, 420, 22, "Ignorer SSL-certifikatfejl")
    ButtonGadget(#G_SrvNew,   215, 250, 95, 28, "Ny")
    ButtonGadget(#G_SrvSave,  318, 250, 95, 28, "Gem")
    ButtonGadget(#G_SrvDel,   421, 250, 95, 28, "Slet")
    ButtonGadget(#G_SrvClose, 540, 250, 95, 28, "Luk")

    ForEach Servers() : AddGadgetItem(#G_SrvList, -1, Servers()\name) : Next
    If CurServer >= 0
      SetGadgetState(#G_SrvList, CurServer)
      SelectElement(Servers(), CurServer)
      SetGadgetText(#G_SrvName, Servers()\name) : SetGadgetText(#G_SrvUrl, Servers()\url)
      SetGadgetText(#G_SrvUser, Servers()\user) : SetGadgetText(#G_SrvPass, Servers()\pass)
      SetGadgetState(#G_SrvNoSSL, Servers()\noSSL)
    EndIf

    Repeat
      ev = WaitWindowEvent()
      Select ev
        Case #PB_Event_CloseWindow
          If EventWindow() = #WinSrv : quit = #True : EndIf
        Case #PB_Event_Gadget
          Select EventGadget()
            Case #G_SrvList
              sel = GetGadgetState(#G_SrvList)
              If sel >= 0 And SelectElement(Servers(), sel)
                SetGadgetText(#G_SrvName, Servers()\name) : SetGadgetText(#G_SrvUrl, Servers()\url)
                SetGadgetText(#G_SrvUser, Servers()\user) : SetGadgetText(#G_SrvPass, Servers()\pass)
                SetGadgetState(#G_SrvNoSSL, Servers()\noSSL)
              EndIf
            Case #G_SrvNew
              SetGadgetState(#G_SrvList, -1)
              SetGadgetText(#G_SrvName, "") : SetGadgetText(#G_SrvUrl, "https://")
              SetGadgetText(#G_SrvUser, "") : SetGadgetText(#G_SrvPass, "")
              SetGadgetState(#G_SrvNoSSL, 0)
            Case #G_SrvSave
              url = NormalizeUrl(GetGadgetText(#G_SrvUrl))
              If Trim(GetGadgetText(#G_SrvName)) = "" Or url = ""
                MessageRequester(#APP_NAME, "Udfyld mindst navn og URL.", #PB_MessageRequester_Warning)
              Else
                sel = GetGadgetState(#G_SrvList)
                If sel >= 0 And SelectElement(Servers(), sel)
                  ; opdater eksisterende
                Else
                  LastElement(Servers())
                  AddElement(Servers())
                  sel = ListIndex(Servers())
                EndIf
                Servers()\name  = Trim(GetGadgetText(#G_SrvName))
                Servers()\url   = url
                Servers()\user  = GetGadgetText(#G_SrvUser)
                Servers()\pass  = GetGadgetText(#G_SrvPass)
                Servers()\noSSL = GetGadgetState(#G_SrvNoSSL)
                If CurServer < 0 : CurServer = sel : EndIf
                ClearGadgetItems(#G_SrvList)
                ForEach Servers() : AddGadgetItem(#G_SrvList, -1, Servers()\name) : Next
                SetGadgetState(#G_SrvList, sel)
                SetGadgetText(#G_SrvUrl, url)
              EndIf
            Case #G_SrvDel
              sel = GetGadgetState(#G_SrvList)
              If sel >= 0 And SelectElement(Servers(), sel)
                DeleteElement(Servers())
                If CurServer = sel
                  CurServer = 0
                ElseIf CurServer > sel
                  CurServer - 1
                EndIf
                If CurServer >= ListSize(Servers()) : CurServer = ListSize(Servers()) - 1 : EndIf
                ClearGadgetItems(#G_SrvList)
                ForEach Servers() : AddGadgetItem(#G_SrvList, -1, Servers()\name) : Next
                SetGadgetText(#G_SrvName, "") : SetGadgetText(#G_SrvUrl, "")
                SetGadgetText(#G_SrvUser, "") : SetGadgetText(#G_SrvPass, "")
              EndIf
            Case #G_SrvClose
              quit = #True
          EndSelect
      EndSelect
    Until quit
    CloseWindow(#WinSrv)
  EndIf
  DisableWindow(#Win, #False)
  SetActiveWindow(#Win)
  If CurServer < 0 And ListSize(Servers()) > 0 : CurServer = 0 : EndIf
  SaveServers()
  FillServerCombo()
  ApplyServer()
EndProcedure

;------------------------------------------------------------------------------
; Kommandoer: tilfoej / start / stop / fjern
;------------------------------------------------------------------------------
Procedure.i AddTorrentFile(path.s, start.i, dir.s)
  Protected id.i, size.i, *buf, b64.s, r.s, e.s, method.s = "load.raw_start"
  If start = #False : method = "load.raw" : EndIf
  id = ReadFile(#PB_Any, path)
  If id = 0
    MessageRequester(#APP_NAME, "Kan ikke åbne filen:" + #LF$ + path, #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  size = Lof(id)
  If size <= 0 Or size > 30000000
    CloseFile(id)
    MessageRequester(#APP_NAME, "Ugyldig filstørrelse: " + path, #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  *buf = AllocateMemory(size)
  ReadData(id, *buf, size)
  CloseFile(id)
  b64 = B64(*buf, size)
  FreeMemory(*buf)
  r = LoadCall(method, "<param><value><base64>" + b64 + "</base64></value></param>", dir)
  e = ResultError(r)
  If e <> ""
    MessageRequester(#APP_NAME, "Kunne ikke tilføje " + GetFilePart(path) + ":" + #LF$ + e, #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure AddMagnets(txt.s, start.i, dir.s)
  Protected i.i, n.i, ln.s, r.s, e.s, firstErr.s = "", method.s = "load.start"
  If start = #False : method = "load.normal" : EndIf
  txt = ReplaceString(txt, #CRLF$, #LF$)
  txt = ReplaceString(txt, #CR$, #LF$)
  n = CountString(txt, #LF$) + 1
  For i = 1 To n
    ln = Trim(StringField(txt, i, #LF$))
    If ln <> "" And (LCase(Left(ln, 7)) = "magnet:" Or LCase(Left(ln, 4)) = "http")
      r = LoadCall(method, PS(ln), dir)
      e = ResultError(r)
      If e <> "" And firstErr = "" : firstErr = e : EndIf
    EndIf
  Next
  If firstErr <> ""
    MessageRequester(#APP_NAME, "Fejl ved tilføjelse: " + firstErr, #PB_MessageRequester_Error)
  EndIf
  gRefresh = 1
EndProcedure

Procedure AddFilesDialog()
  Protected f.s
  If gURL = "" : MessageRequester(#APP_NAME, "Vælg først en server.") : ProcedureReturn : EndIf
  f = OpenFileRequester("Vælg torrent-filer", "", "Torrent-filer (*.torrent)|*.torrent|Alle filer (*.*)|*.*", 0, #PB_Requester_MultiSelection)
  While f <> ""
    AddTorrentFile(f, #True, "")
    f = NextSelectedFileName()
  Wend
  gRefresh = 1
EndProcedure

Procedure MagnetDialog()
  Protected ev.i, quit.i, ok.i, txt.s, dir.s, start.i
  If gURL = "" : MessageRequester(#APP_NAME, "Vælg først en server.") : ProcedureReturn : EndIf
  DisableWindow(#Win, #True)
  If OpenWindow(#WinMag, 0, 0, 540, 320, "Tilføj magnet-links", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#Win))
    ApplyIcon(WindowID(#WinMag))
    TextGadget(#PB_Any, 10, 10, 520, 18, "Magnet-links (ét pr. linje):")
    EditorGadget(#G_MagText, 10, 30, 520, 170)
    TextGadget(#PB_Any, 10, 210, 520, 18, "Gem i mappe på serveren (valgfrit):")
    StringGadget(#G_MagDir, 10, 230, 520, 24, "")
    CheckBoxGadget(#G_MagStart, 10, 262, 300, 22, "Start straks")
    SetGadgetState(#G_MagStart, #PB_Checkbox_Checked)
    ButtonGadget(#G_MagOK, 330, 280, 95, 30, "Tilføj")
    ButtonGadget(#G_MagCancel, 435, 280, 95, 30, "Annuller")
    SetActiveGadget(#G_MagText)
    Repeat
      ev = WaitWindowEvent()
      Select ev
        Case #PB_Event_CloseWindow
          If EventWindow() = #WinMag : quit = #True : EndIf
        Case #PB_Event_Gadget
          Select EventGadget()
            Case #G_MagOK
              txt = GetGadgetText(#G_MagText)
              dir = Trim(GetGadgetText(#G_MagDir))
              start = GetGadgetState(#G_MagStart)
              ok = #True
              quit = #True
            Case #G_MagCancel
              quit = #True
          EndSelect
      EndSelect
    Until quit
    CloseWindow(#WinMag)
  EndIf
  DisableWindow(#Win, #False)
  SetActiveWindow(#Win)
  If ok : AddMagnets(txt, start, dir) : EndIf
EndProcedure

Procedure DoAction(methods.s, all.i)
  Protected NewList h.s()
  Protected r.s, e.s
  If all
    ForEach Tor() : AddElement(h()) : h() = Tor()\hash : Next
  Else
    GetSelectedHashes(h())
  EndIf
  If ListSize(h()) = 0 : ProcedureReturn : EndIf
  r = MultiCall(methods, h())
  e = ResultError(r)
  If e <> "" : MessageRequester(#APP_NAME, "Fejl: " + e, #PB_MessageRequester_Error) : EndIf
  gRefresh = 1
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

; Stopper, sletter data paa serveren (rm -rf) og fjerner derefter torrenten
Procedure DeleteWithData(List h.s())
  Protected NewList L.s()
  Protected r.s, e.s, path.s, nm.s, failed.s = "", idx.i = 0, skipped.i = 0, n.i = ListSize(h())

  r = MultiCall("d.base_path|d.name", h())
  e = ResultError(r)
  If e <> ""
    MessageRequester(#APP_NAME, "Kunne ikke finde filernes placering:" + #LF$ + e + #LF$ + "Intet er slettet.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  ParseLeaves(r, L())
  If ListSize(L()) <> n * 2
    MessageRequester(#APP_NAME, "Serveren gav uventede svar om filernes placering." + #LF$ + "Intet er slettet.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf

  MultiCall("d.stop|d.close", h())

  ForEach L()
    If idx % 2 = 0
      path = L()
    Else
      nm = L()
      If SafeDataPath(path, nm)
        r = CurCall(MakeXml("execute.nothrow.bg", PS("") + PS("rm") + PS("-rf") + PS("--") + PS(path)))
        e = ResultError(r)
        If e <> "" : failed = e : EndIf
      Else
        skipped + 1
      EndIf
    EndIf
    idx + 1
  Next

  MultiCall("d.erase", h())
  gRefresh = 1

  If failed <> ""
    MessageRequester(#APP_NAME, "Serveren afviste sletning af filer:" + #LF$ + failed + #LF$ + "Torrenten er fjernet, men filerne kan ligge tilbage.", #PB_MessageRequester_Warning)
  ElseIf skipped > 0
    MessageRequester(#APP_NAME, Str(skipped) + " torrent(s) fik ikke slettet filer, fordi stien ikke kunne bekræftes som sikker." + #LF$ + "Selve torrenterne er fjernet.", #PB_MessageRequester_Warning)
  EndIf
EndProcedure

; withData = #False: fjern kun torrenten. #True: slet ogsaa filerne paa serveren (efter bekraeftelse)
Procedure RemoveSelected(withData.i)
  Protected NewList h.s()
  Protected info.s, shown.i = 0
  GetSelectedHashes(h())
  If ListSize(h()) = 0 : ProcedureReturn : EndIf
  If withData = #False
    DoAction("d.erase", #False)
    ProcedureReturn
  EndIf

  info = "Slet " + Str(ListSize(h())) + " torrent(s) og deres filer på serveren?" + #LF$
  ForEach h()
    ForEach Tor()
      If Tor()\hash = h()
        If shown < 4 : info + #LF$ + "  " + Tor()\name : EndIf
        shown + 1
        Break
      EndIf
    Next
  Next
  If ListSize(h()) > 4 : info + #LF$ + "  ... og " + Str(ListSize(h()) - 4) + " mere" : EndIf

  info + #LF$ + #LF$ + "Filerne slettes permanent og kan ikke fortrydes."

  If MessageRequester("Slet torrent + data", info, #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) = #PB_MessageRequester_Yes
    DeleteWithData(h())
  EndIf
EndProcedure

Procedure ApplyColumns()
  Protected c.i
  For c = 1 To 11
    If gColVisible(c)
      SetGadgetItemAttribute(#G_List, 0, #PB_ListIcon_ColumnWidth, gColWidth(c), c)
    Else
      SetGadgetItemAttribute(#G_List, 0, #PB_ListIcon_ColumnWidth, 0, c)
    EndIf
  Next
EndProcedure

Procedure ToggleColumn(c.i)
  If c < 1 Or c > 11 : ProcedureReturn : EndIf
  CaptureColumns()
  gColVisible(c) = 1 - gColVisible(c)
  If gColVisible(c) And gColWidth(c) < 30 : gColWidth(c) = 80 : EndIf
  ApplyColumns()
  SaveServers()
EndProcedure

Procedure ShowColumnMenu()
  Protected c.i
  If IsMenu(2) : FreeMenu(2) : EndIf
  If CreatePopupMenu(2)
    For c = 1 To 11
      MenuItem(#M_ColBase + c, gColName(c))
      SetMenuItemState(2, #M_ColBase + c, gColVisible(c))
    Next
    DisplayPopupMenu(2, WindowID(#Win))
  EndIf
EndProcedure

Procedure TestConnection()
  Protected r1.s, r2.s, msg.s
  If gURL = ""
    MessageRequester(#APP_NAME, "Ingen server valgt.")
    ProcedureReturn
  EndIf
  r1 = CurCall(MakeXml("system.client_version", ""))
  msg = "URL: " + gURL + #LF$ + "Bruger: " + gUser + #LF$ + #LF$ + "system.client_version:" + #LF$ + Left(r1, 400)
  If Left(r1, 4) <> "ERR:" And ResultError(r1) = ""
    r2 = CurCall(ListCall())
    msg + #LF$ + #LF$ + "d.multicall2 (" + Str(Len(r2)) + " tegn):" + #LF$ + Left(r2, 500)
  EndIf
  MessageRequester(#APP_NAME + " - test af forbindelse", msg)
EndProcedure

Declare Layout()

Procedure ToggleSidebar()
  gSidebar = 1 - gSidebar
  SetMenuItemState(0, #M_Sidebar, gSidebar)
  HideGadget(#G_Filter, 1 - gSidebar)
  Layout()
  SaveServers()
EndProcedure

Procedure HandleCommand(cmd.i)
  If cmd > #M_ColBase And cmd <= #M_ColBase + 11
    ToggleColumn(cmd - #M_ColBase)
    ProcedureReturn
  EndIf
  Select cmd
    Case #M_AddFile    : AddFilesDialog()
    Case #M_AddMagnet  : MagnetDialog()
    Case #M_Start      : DoAction("d.start|d.resume", #False)
    Case #M_Stop       : DoAction("d.stop|d.close", #False)
    Case #M_StartAll   : DoAction("d.start|d.resume", #True)
    Case #M_StopAll    : DoAction("d.stop|d.close", #True)
    Case #M_Recheck    : DoAction("d.check_hash", #False)
    Case #M_RemoveTorrent : RemoveSelected(#False)
    Case #M_RemoveData    : RemoveSelected(#True)
    Case #M_Servers    : ServerDialog()
    Case #M_Refresh    : gRefresh = 1
    Case #M_Test       : TestConnection()
    Case #M_Sidebar    : ToggleSidebar()
    Case #M_About
      MessageRequester("Om " + #APP_NAME, #APP_NAME + " - rTorrent-klient via XML-RPC" + #LF$ + "Skrevet i PureBasic.")
    Case #M_Quit       : PostEvent(#PB_Event_CloseWindow, #Win, 0)
  EndSelect
EndProcedure

Procedure OnDrop()
  Protected f.s, i.i, n.i, t.s
  Select EventDropType()
    Case #PB_Drop_Files
      f = EventDropFiles()
      n = CountString(f, #LF$) + 1
      For i = 1 To n
        t = StringField(f, i, #LF$)
        If LCase(GetExtensionPart(t)) = "torrent" : AddTorrentFile(t, #True, "") : EndIf
      Next
      gRefresh = 1
    Case #PB_Drop_Text
      AddMagnets(EventDropText(), #True, "")
  EndSelect
EndProcedure

;------------------------------------------------------------------------------
; Ikoner til vaerktoejslinjen (tegnes som vektorgrafik i et 24x24-gitter)
;------------------------------------------------------------------------------
Enumeration
  #Ico_AddFile
  #Ico_AddMagnet
  #Ico_Start
  #Ico_Stop
  #Ico_Remove
  #Ico_Servers
EndEnumeration

Procedure PathRoundBox(x.d, y.d, w.d, h.d, r.d)
  MovePathCursor(x + r, y)
  AddPathArc(x + w, y, x + w, y + h, r)
  AddPathArc(x + w, y + h, x, y + h, r)
  AddPathArc(x, y + h, x, y, r)
  AddPathArc(x, y, x + w, y, r)
  ClosePath()
EndProcedure

Procedure.i MakeIcon(kind.i)
  Protected sz.i = Round(20 * DesktopResolutionX(), #PB_Round_Nearest)
  Protected img.i = CreateImage(#PB_Any, sz, sz, 32, #PB_Image_Transparent)
  If img = 0 : ProcedureReturn 0 : EndIf
  If StartVectorDrawing(ImageVectorOutput(img))
    ScaleCoordinates(sz / 24.0, sz / 24.0)
    Select kind
      Case #Ico_AddFile
        ; dokument med foldet hjoerne + groent plus
        MovePathCursor(4, 2) : AddPathLine(13, 2) : AddPathLine(18, 7) : AddPathLine(18, 22) : AddPathLine(4, 22) : ClosePath()
        VectorSourceColor(RGBA(255, 255, 255, 255)) : FillPath(#PB_Path_Preserve)
        VectorSourceColor(RGBA(90, 100, 112, 255)) : StrokePath(1.5, #PB_Path_RoundCorner)
        MovePathCursor(13, 2) : AddPathLine(13, 7) : AddPathLine(18, 7)
        StrokePath(1.5, #PB_Path_RoundCorner)
        AddPathCircle(17, 17, 6)
        VectorSourceColor(RGBA(46, 158, 71, 255)) : FillPath()
        MovePathCursor(17, 13.5) : AddPathLine(17, 20.5)
        MovePathCursor(13.5, 17) : AddPathLine(20.5, 17)
        VectorSourceColor(RGBA(255, 255, 255, 255)) : StrokePath(2)
      Case #Ico_AddMagnet
        ; hesteskomagnet
        MovePathCursor(6, 3) : AddPathArc(6, 20, 18, 20, 6) : AddPathArc(18, 20, 18, 3, 6) : AddPathLine(18, 3)
        VectorSourceColor(RGBA(214, 69, 65, 255)) : StrokePath(5)
        MovePathCursor(6, 2) : AddPathLine(6, 7)
        MovePathCursor(18, 2) : AddPathLine(18, 7)
        VectorSourceColor(RGBA(150, 160, 170, 255)) : StrokePath(5)
      Case #Ico_Start
        MovePathCursor(7, 4) : AddPathLine(20, 12) : AddPathLine(7, 20) : ClosePath()
        VectorSourceColor(RGBA(46, 158, 71, 255))
        FillPath(#PB_Path_Preserve) : StrokePath(2, #PB_Path_RoundCorner)
      Case #Ico_Stop
        PathRoundBox(5, 5, 14, 14, 2)
        VectorSourceColor(RGBA(79, 93, 107, 255)) : FillPath()
      Case #Ico_Remove
        ; skraldespand
        VectorSourceColor(RGBA(214, 69, 65, 255))
        MovePathCursor(9, 6) : AddPathLine(9, 3.5) : AddPathLine(15, 3.5) : AddPathLine(15, 6)
        StrokePath(1.8, #PB_Path_RoundCorner)
        MovePathCursor(4, 6.5) : AddPathLine(20, 6.5)
        StrokePath(2.2, #PB_Path_RoundEnd)
        MovePathCursor(6, 9) : AddPathLine(7.2, 21) : AddPathLine(16.8, 21) : AddPathLine(18, 9) : ClosePath()
        FillPath()
        MovePathCursor(10, 11.5) : AddPathLine(10, 18.5)
        MovePathCursor(14, 11.5) : AddPathLine(14, 18.5)
        VectorSourceColor(RGBA(255, 255, 255, 255)) : StrokePath(1.5, #PB_Path_RoundEnd)
      Case #Ico_Servers
        ; to serverenheder i et rack
        PathRoundBox(3, 3, 18, 8, 2)
        PathRoundBox(3, 13, 18, 8, 2)
        VectorSourceColor(RGBA(79, 93, 107, 255)) : FillPath()
        AddPathCircle(7.5, 7, 1.4)
        AddPathCircle(7.5, 17, 1.4)
        VectorSourceColor(RGBA(120, 220, 110, 255)) : FillPath()
        MovePathCursor(12, 7) : AddPathLine(17.5, 7)
        MovePathCursor(12, 17) : AddPathLine(17.5, 17)
        VectorSourceColor(RGBA(200, 208, 216, 255)) : StrokePath(1.5, #PB_Path_RoundEnd)
    EndSelect
    StopVectorDrawing()
  EndIf
  ProcedureReturn img
EndProcedure

Procedure IconButton(gad.i, x.i, kind.i, tip.s)
  ButtonImageGadget(gad, x, 4, 34, 30, ImageID(MakeIcon(kind)))
  GadgetToolTip(gad, tip)
EndProcedure

;------------------------------------------------------------------------------
; Layout og vindue
;------------------------------------------------------------------------------
Procedure Layout()
  Protected w.i, h.i, top.i = 38, side.i = 0, detH.i, listH.i, iw.i, ih.i
  w = WindowWidth(#Win)
  h = WindowHeight(#Win) - StatusBarHeight(0)
  detH = h * 36 / 100
  listH = h - top - detH
  If listH < 60 : listH = 60 : EndIf
  If gSidebar : side = 190 : EndIf
  ResizeGadget(#G_SearchLbl, w - 300, 11, 44, 20)
  ResizeGadget(#G_Search, w - 252, 6, 244, 26)
  ResizeGadget(#G_Filter, 0, top, side, h - top)
  ResizeGadget(#G_List, side, top, w - side, listH)
  ResizeGadget(#G_Panel, side, top + listH, w - side, h - top - listH)
  iw = GetGadgetAttribute(#G_Panel, #PB_Panel_ItemWidth)
  ih = GetGadgetAttribute(#G_Panel, #PB_Panel_ItemHeight)
  ResizeGadget(#G_General, 0, 0, iw, ih)
  ResizeGadget(#G_Trackers, 0, 0, iw, ih)
  ResizeGadget(#G_Peers, 0, 0, iw, ih)
  ResizeGadget(#G_Files, 0, 0, iw, ih)
EndProcedure

; Henter det kørende vindue frem (bruges naar man starter programmet en gang til)
Procedure ShowMainWindow()
  If IsWindow(#Win) = 0 : ProcedureReturn : EndIf
  If GetWindowState(#Win) = #PB_Window_Minimize
    ShowWindow_(WindowID(#Win), #SW_RESTORE)
  EndIf
  HideWindow(#Win, #False)
  SetForegroundWindow_(WindowID(#Win))
EndProcedure

; Tegner en blaa forloebsbjaelke i en celle i torrentlisten
Procedure DrawProgressCell(base.i)
  Protected lv.i = GadgetID(#G_List)
  Protected hdc.i = PeekI(base + #MY_OFF_HDC)
  Protected item.i = PeekI(base + #MY_OFF_ITEM)
  Protected rc.RECT, bar.RECT, fl.RECT
  Protected br.i, bg.i, sel.i, p.d = 0, txt.s, wd.i
  rc\left = 0
  rc\top = #MY_COL_PROGRESS
  If SendMessage_(lv, #LVM_GETSUBITEMRECT, item, @rc) = 0 : ProcedureReturn : EndIf
  If item >= 0 And item < gShownN : p = gShownProg(item) : EndIf
  If p < 0 : p = 0 : EndIf
  If p > 100 : p = 100 : EndIf

  sel = Bool(SendMessage_(lv, #LVM_GETITEMSTATE, item, #LVIS_SELECTED) & #LVIS_SELECTED)
  If sel
    If GetFocus_() = lv
      bg = GetSysColor_(#COLOR_HIGHLIGHT)
    Else
      bg = GetSysColor_(#COLOR_BTNFACE)
    EndIf
  Else
    bg = GetSysColor_(#COLOR_WINDOW)
  EndIf
  br = CreateSolidBrush_(bg) : FillRect_(hdc, @rc, br) : DeleteObject_(br)

  bar\left = rc\left + 3 : bar\top = rc\top + 3 : bar\right = rc\right - 3 : bar\bottom = rc\bottom - 3
  br = CreateSolidBrush_(RGB(228, 228, 228)) : FillRect_(hdc, @bar, br) : DeleteObject_(br)

  wd = Int((bar\right - bar\left) * p / 100)
  If wd > 0
    fl\left = bar\left : fl\top = bar\top : fl\bottom = bar\bottom : fl\right = bar\left + wd
    br = CreateSolidBrush_(RGB(38, 118, 235)) : FillRect_(hdc, @fl, br) : DeleteObject_(br)
  EndIf
  br = CreateSolidBrush_(RGB(165, 165, 165)) : FrameRect_(hdc, @bar, br) : DeleteObject_(br)

  txt = StrD(p, 1) + " %"
  SetBkMode_(hdc, #TRANSPARENT)
  If p >= 50
    SetTextColor_(hdc, RGB(255, 255, 255))
  Else
    SetTextColor_(hdc, RGB(0, 0, 0))
  EndIf
  DrawText_(hdc, @txt, -1, @bar, #DT_CENTER | #DT_VCENTER | #DT_SINGLELINE)
EndProcedure

; Lytter paa hoejreklik direkte paa kolonne-overskriften
Procedure HdrProc(hwnd, msg, wparam, lparam)
  If msg = #WM_RBUTTONUP
    PostEvent(#EvHdrMenu, #Win, 0)
    ProcedureReturn 0
  EndIf
  ProcedureReturn CallWindowProc_(gOldHdr, hwnd, msg, wparam, lparam)
EndProcedure

Procedure WinCb(hwnd, msg, wparam, lparam)
  Protected *nm.MY_NMLV
  If gShowMsg <> 0 And msg = gShowMsg
    ShowMainWindow()
    ProcedureReturn 0
  EndIf
  If msg = #WM_NOTIFY
    *nm = lparam
    If *nm\hdr\hwndFrom = GadgetID(#G_List)
      If *nm\hdr\code = #MY_LVN_COLUMNCLICK
        gSortReq = *nm\iSubItem
        PostEvent(#EvSort, #Win, 0)
      ElseIf *nm\hdr\code = -12
        Select PeekL(lparam + #MY_OFF_STAGE)
          Case 1
            ProcedureReturn $20
          Case $10001
            ProcedureReturn $20
          Case $30001
            If PeekL(lparam + #MY_OFF_SUB) = #MY_COL_PROGRESS
              DrawProgressCell(lparam)
              ProcedureReturn 4
            EndIf
        EndSelect
      EndIf
    EndIf
  EndIf
  ProcedureReturn #PB_ProcessPureBasicEvents
EndProcedure

;==============================================================================
; Hovedprogram
;==============================================================================
Define ev.i, quit.i, i.i

; Kun én instans ad gangen
gInstMutex = CreateMutex_(0, 1, "rTorrentRemote_SingleInstance_Mutex")
If GetLastError_() = 183   ; ERROR_ALREADY_EXISTS
  AllowSetForegroundWindow_(-1)
  PostMessage_($FFFF, gShowMsg, 0, 0)
  End
EndIf

gFilterName(0) = "Alle"
gFilterName(1) = "Henter"
gFilterName(2) = "Seeder"
gFilterName(3) = "Færdige"
gFilterName(4) = "Stoppede"
gFilterName(5) = "Aktive"
gFilterName(6) = "Inaktive"
gFilterName(7) = "Fejl"

Define cn.s = "Navn|Størrelse|Forløb|Status|Seeds|Peers|Down-hastighed|Up-hastighed|ETA|Seedtid|Ratio|Label"
Define cw.s = "340|85|150|80|55|55|100|100|80|90|60|100"
For i = 0 To 11
  gColName(i) = StringField(cn, i + 1, "|")
  gColWidth(i) = Val(StringField(cw, i + 1, "|"))
  gColVisible(i) = 1
Next

LoadServers()

Define wflags.i = #PB_Window_SystemMenu | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget
Define wx.i = 0, wy.i = 0, ww.i = 1200, wh.i = 720
If gWinValid And OnAnyDesktop(gWinX + 40, gWinY + 20)
  wx = gWinX : wy = gWinY : ww = gWinW : wh = gWinH
Else
  wflags | #PB_Window_ScreenCentered
EndIf
If OpenWindow(#Win, wx, wy, ww, wh, #APP_NAME, wflags) = 0
  End
EndIf
WindowBounds(#Win, 900, 520, #PB_Ignore, #PB_Ignore)
ApplyIcon(WindowID(#Win))

If CreateMenu(0, WindowID(#Win))
  MenuTitle("Fil")
  MenuItem(#M_AddFile, "Tilføj torrent-fil..." + #TAB$ + "Ctrl+O")
  MenuItem(#M_AddMagnet, "Tilføj magnet-link..." + #TAB$ + "Ctrl+U")
  MenuBar()
  MenuItem(#M_Quit, "Afslut")
  MenuTitle("Torrent")
  MenuItem(#M_Start, "Start")
  MenuItem(#M_Stop, "Stop")
  MenuItem(#M_StartAll, "Start alle")
  MenuItem(#M_StopAll, "Stop alle")
  MenuBar()
  MenuItem(#M_Recheck, "Gentjek hash")
  OpenSubMenu("Fjern")
    MenuItem(#M_RemoveTorrent, "Slet torrent")
    MenuItem(#M_RemoveData, "Slet torrent + data...")
  CloseSubMenu()
  MenuTitle("Server")
  MenuItem(#M_Servers, "Administrer servere...")
  MenuItem(#M_Refresh, "Opdater nu" + #TAB$ + "F5")
  MenuItem(#M_Test, "Test forbindelse...")
  MenuTitle("Vis")
  MenuItem(#M_Sidebar, "Sidebjælke" + #TAB$ + "Ctrl+B")
  SetMenuItemState(0, #M_Sidebar, gSidebar)
  MenuTitle("Hjælp")
  MenuItem(#M_About, "Om...")
EndIf
If CreatePopupMenu(1)
  MenuItem(#M_Start, "Start")
  MenuItem(#M_Stop, "Stop")
  MenuBar()
  MenuItem(#M_Recheck, "Gentjek hash")
  OpenSubMenu("Fjern")
    MenuItem(#M_RemoveTorrent, "Slet torrent")
    MenuItem(#M_RemoveData, "Slet torrent + data...")
  CloseSubMenu()
EndIf
If CreatePopupMenu(3)
  MenuItem(#M_RemoveTorrent, "Slet torrent")
  MenuItem(#M_RemoveData, "Slet torrent + data...")
EndIf
AddKeyboardShortcut(#Win, #PB_Shortcut_Control | #PB_Shortcut_O, #M_AddFile)
AddKeyboardShortcut(#Win, #PB_Shortcut_Control | #PB_Shortcut_U, #M_AddMagnet)
AddKeyboardShortcut(#Win, #PB_Shortcut_F5, #M_Refresh)
AddKeyboardShortcut(#Win, #PB_Shortcut_Control | #PB_Shortcut_B, #M_Sidebar)

CreateStatusBar(0, WindowID(#Win))
AddStatusBarField(380)
AddStatusBarField(140)
AddStatusBarField(140)
AddStatusBarField(#PB_Ignore)

; værktøjslinje
IconButton(#G_BtnAddFile,   6,   #Ico_AddFile,   "Tilføj torrent-fil (Ctrl+O)")
IconButton(#G_BtnAddMagnet, 42,  #Ico_AddMagnet, "Tilføj magnet-link (Ctrl+U)")
IconButton(#G_BtnStart,     88,  #Ico_Start,     "Start valgte torrents")
IconButton(#G_BtnStop,      124, #Ico_Stop,      "Stop valgte torrents")
IconButton(#G_BtnRemove,    160, #Ico_Remove,    "Fjern valgte torrents")
ComboBoxGadget(#G_Server,   208, 6, 190, 26)
GadgetToolTip(#G_Server, "Aktiv server")
IconButton(#G_BtnServers,   402, #Ico_Servers,   "Administrer servere...")
TextGadget(#G_SearchLbl, 0, 0, 44, 20, "Søg:")
StringGadget(#G_Search, 0, 0, 100, 26, "")

; sidebjælke (statusfiltre)
ListViewGadget(#G_Filter, 0, 0, 100, 100)
For i = 0 To 7
  gFilterTxt(i) = gFilterName(i) + " (0)"
  AddGadgetItem(#G_Filter, -1, gFilterTxt(i))
Next
SetGadgetState(#G_Filter, 0)
HideGadget(#G_Filter, 1 - gSidebar)

; torrent-liste
ListIconGadget(#G_List, 0, 0, 100, 100, "Navn", 340, #PB_ListIcon_FullRowSelect | #PB_ListIcon_MultiSelect | #PB_ListIcon_AlwaysShowSelection)
AddGadgetColumn(#G_List, 1, "Størrelse", 85)
AddGadgetColumn(#G_List, 2, "Forløb", 150)
AddGadgetColumn(#G_List, 3, "Status", 80)
AddGadgetColumn(#G_List, 4, "Seeds", 55)
AddGadgetColumn(#G_List, 5, "Peers", 55)
AddGadgetColumn(#G_List, 6, "Down-hastighed", 100)
AddGadgetColumn(#G_List, 7, "Up-hastighed", 100)
AddGadgetColumn(#G_List, 8, "ETA", 80)
AddGadgetColumn(#G_List, 9, "Seedtid", 90)
AddGadgetColumn(#G_List, 10, "Ratio", 60)
AddGadgetColumn(#G_List, 11, "Label", 100)

; detaljepanel med faneblade
PanelGadget(#G_Panel, 0, 0, 100, 100)
  AddGadgetItem(#G_Panel, -1, "Generelt")
  ListIconGadget(#G_General, 0, 0, 100, 100, "Egenskab", 160, #PB_ListIcon_FullRowSelect)
  AddGadgetColumn(#G_General, 1, "Værdi", 700)
  AddGadgetItem(#G_Panel, -1, "Trackere")
  ListIconGadget(#G_Trackers, 0, 0, 100, 100, "URL", 420, #PB_ListIcon_FullRowSelect)
  AddGadgetColumn(#G_Trackers, 1, "Status", 90)
  AddGadgetColumn(#G_Trackers, 2, "Seeds", 70)
  AddGadgetColumn(#G_Trackers, 3, "Peers", 70)
  AddGadgetColumn(#G_Trackers, 4, "Downloads", 90)
  AddGadgetItem(#G_Panel, -1, "Peers")
  ListIconGadget(#G_Peers, 0, 0, 100, 100, "IP", 160, #PB_ListIcon_FullRowSelect)
  AddGadgetColumn(#G_Peers, 1, "Port", 60)
  AddGadgetColumn(#G_Peers, 2, "Klient", 180)
  AddGadgetColumn(#G_Peers, 3, "Forløb", 80)
  AddGadgetColumn(#G_Peers, 4, "Down", 100)
  AddGadgetColumn(#G_Peers, 5, "Up", 100)
  AddGadgetItem(#G_Panel, -1, "Indhold")
  ListIconGadget(#G_Files, 0, 0, 100, 100, "Sti", 500, #PB_ListIcon_FullRowSelect)
  AddGadgetColumn(#G_Files, 1, "Størrelse", 90)
  AddGadgetColumn(#G_Files, 2, "Forløb", 150)
  AddGadgetColumn(#G_Files, 3, "Prioritet", 90)
CloseGadgetList()

; faste rækker i "Generelt"
Define lbl.s
For i = 0 To 14
  Select i
    Case 0  : lbl = "Navn"
    Case 1  : lbl = "Hash"
    Case 2  : lbl = "Gemmes i"
    Case 3  : lbl = "Størrelse"
    Case 4  : lbl = "Hentet"
    Case 5  : lbl = "Forløb"
    Case 6  : lbl = "Status"
    Case 7  : lbl = "Seeds"
    Case 8  : lbl = "Peers"
    Case 9  : lbl = "Ratio"
    Case 10 : lbl = "Uploadet i alt"
    Case 11 : lbl = "Downloadet i alt"
    Case 12 : lbl = "Label"
    Case 13 : lbl = "Besked"
    Case 14 : lbl = "Seedet i"
  EndSelect
  AddGadgetItem(#G_General, -1, lbl + #LF$ + "")
Next

ApplyColumns()
gOldHdr = SetWindowLongPtr_(SendMessage_(GadgetID(#G_List), #LVM_GETHEADER, 0, 0), #GWL_WNDPROC, @HdrProc())
EnableWindowDrop(#Win, #PB_Drop_Files, #PB_Drag_Copy)
EnableWindowDrop(#Win, #PB_Drop_Text, #PB_Drag_Copy)
SetWindowCallback(@WinCb(), #Win)

If gWinMax : SetWindowState(#Win, #PB_Window_Maximize) : EndIf
Layout()
FillServerCombo()
ApplyServer()
gThread = CreateThread(@PollThread(), 0)

If ListSize(Servers()) = 0
  ServerDialog()
EndIf

Repeat
  ev = WaitWindowEvent()
  Select ev
    Case #PB_Event_SizeWindow  : Layout() : CaptureWindow()
    Case #PB_Event_MoveWindow  : CaptureWindow()
    Case #PB_Event_CloseWindow : quit = #True
    Case #EvPoll               : OnPoll()
    Case #EvSort               : OnSort()
    Case #EvHdrMenu            : ShowColumnMenu()
    Case #PB_Event_WindowDrop  : OnDrop()
    Case #PB_Event_Menu        : HandleCommand(EventMenu())
    Case #PB_Event_Gadget
      Select EventGadget()
        Case #G_BtnAddFile   : HandleCommand(#M_AddFile)
        Case #G_BtnAddMagnet : HandleCommand(#M_AddMagnet)
        Case #G_BtnStart     : HandleCommand(#M_Start)
        Case #G_BtnStop      : HandleCommand(#M_Stop)
        Case #G_BtnRemove    : DisplayPopupMenu(3, WindowID(#Win))
        Case #G_BtnServers   : HandleCommand(#M_Servers)
        Case #G_Server
          i = GetGadgetState(#G_Server)
          If i >= 0 And i <> CurServer
            CurServer = i
            SaveServers()
            ApplyServer()
          EndIf
        Case #G_Filter
          i = GetGadgetState(#G_Filter)
          If i >= 0 : gFilter = i : RefreshList() : OnSelection() : EndIf
        Case #G_Search
          If EventType() = #PB_EventType_Change : RefreshList() : OnSelection() : EndIf
        Case #G_List
          Select EventType()
            Case #PB_EventType_Change     : OnSelection()
            Case #PB_EventType_RightClick : DisplayPopupMenu(1, WindowID(#Win))
          EndSelect
        Case #G_Panel
          LockMutex(gMutex)
          gDetTab = GetGadgetState(#G_Panel)
          UnlockMutex(gMutex)
          gRefresh = 1
      EndSelect
  EndSelect
Until quit

gQuit = 1
If IsThread(gThread)
  If WaitThread(gThread, 4000) = 0 : KillThread(gThread) : EndIf
EndIf
SaveServers()
End

; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 1828
; FirstLine = 1781
; Folding = ------------
; EnableThread
; EnableXP
; DPIAware
; UseIcon = rtorrent_remote.ico
; Executable = rtorrent_remote.exe
; IncludeVersionInfo
; VersionField0 = 1.0.0.0
; VersionField1 = 1.0