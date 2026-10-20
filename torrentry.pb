;==============================================================================
; Torrentry - Windows-fjernbetjening til torrentklienter, skrevet i PureBasic
;
; Krav:     PureBasic 6.x (x64 anbefales)
;           Compiler > Compiler Options > "Create threadsafe executable" = TIL
; Klienter: rTorrent (XML-RPC), Transmission, qBittorrent og Deluge (Web UI)
;           - se backend.pbi og backend_*.pbi
;==============================================================================
EnableExplicit

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Slaa 'Create threadsafe executable' til (Compiler > Compiler Options)."
CompilerEndIf

#APP_NAME           = "Torrentry"
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
  #G_SrvType
  #G_SrvName
  #G_SrvUrlLbl
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

XIncludeFile "backend.pbi"

Structure Server
  name.s
  type.i
  url.s
  user.s
  pass.s
  noSSL.i
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
Global gThread.i, gQuit.i, gRefresh.i
Global gConn.Conn
Global gDetTab.i, gDetHash.s
Global gListRaw.s, gDetRaw.s, gResTab.i, gResHash.s, gResType.i

Global gShownErr.s
Global gInstMutex.i
Global gShowMsg.i = RegisterWindowMessage_("Torrentry_ShowWindow")
Global gWinX.i, gWinY.i, gWinW.i, gWinH.i, gWinMax.i, gWinValid.i
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

;------------------------------------------------------------------------------
; Torrent-data
;------------------------------------------------------------------------------
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

Procedure UpdateDetails(type.i, det.s, tab.i, hash.s)
  Protected NewList tr.TrackerInfo()
  Protected NewList pe.PeerInfo()
  Protected NewList fi.FileInfo()
  Protected st.s, pr.s
  If tab <> gDetTab Or hash <> gDetHash : ProcedureReturn : EndIf
  If det = "" Or Backend_DetailsError(type, det) <> "" : ProcedureReturn : EndIf
  Select tab
    Case 1
      Backend_ParseTrackers(type, det, tr())
      ClearGadgetItems(#G_Trackers)
      ForEach tr()
        If tr()\enabled : st = "Aktiv" : Else : st = "Deaktiveret" : EndIf
        AddGadgetItem(#G_Trackers, -1, tr()\url + #LF$ + st + #LF$ + Str(tr()\seeds) + #LF$ + Str(tr()\peers) + #LF$ + Str(tr()\downloads))
      Next
    Case 2
      Backend_ParsePeers(type, det, pe())
      ClearGadgetItems(#G_Peers)
      ForEach pe()
        AddGadgetItem(#G_Peers, -1, pe()\ip + #LF$ + Str(pe()\port) + #LF$ + pe()\client + #LF$ + StrD(pe()\progress, 0) + " %" + #LF$ + FmtSpeed(pe()\downRate) + #LF$ + FmtSpeed(pe()\upRate))
      Next
    Case 3
      Backend_ParseFiles(type, det, fi())
      ClearGadgetItems(#G_Files)
      ForEach fi()
        Select fi()\priority
          Case 0 : pr = "Spring over"
          Case 2 : pr = "Høj"
          Default : pr = "Normal"
        EndSelect
        AddGadgetItem(#G_Files, -1, fi()\path + #LF$ + FmtSize(fi()\size) + #LF$ + ProgText(fi()\progress) + #LF$ + pr)
      Next
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
  Protected raw.s, det.s, tab.i, hash.s, type.i, e.s
  Protected dl.q, ul.q, srv.s = ""
  LockMutex(gMutex)
  raw = gListRaw : det = gDetRaw : tab = gResTab : hash = gResHash : type = gResType
  UnlockMutex(gMutex)
  If raw = "" : ProcedureReturn : EndIf
  If CurServer >= 0 And SelectElement(Servers(), CurServer) : srv = Servers()\name : EndIf

  e = Backend_ListError(type, raw)
  If e <> ""
    StatusBarText(0, 0, "Fejl: " + e)
    If e <> gShownErr
      gShownErr = e
      MessageRequester(#APP_NAME, "Kunne ikke hente listen:" + #LF$ + e + #LF$ + #LF$ + "Brug Server > Test forbindelse for flere detaljer.", #PB_MessageRequester_Error)
    EndIf
    ProcedureReturn
  EndIf
  gShownErr = ""

  Backend_ParseList(type, raw, Tor())
  SortTorrents()
  RefreshList()
  OnSelection()
  UpdateDetails(type, det, tab, hash)

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
  Protected c.Conn, tab.i, hash.s, resp.s, det.s, i.i
  While gQuit = 0
    LockMutex(gMutex)
    CopyStructure(@gConn, @c, Conn)
    tab = gDetTab : hash = gDetHash
    UnlockMutex(gMutex)
    gRefresh = 0

    If c\url <> ""
      resp = Backend_FetchList(@c)
      det = ""
      If tab > 0 And hash <> "" And Backend_ListError(c\type, resp) = ""
        det = Backend_FetchDetails(@c, tab, hash)
      EndIf
      LockMutex(gMutex)
      If c\url = gConn\url And c\type = gConn\type
        gListRaw = resp : gDetRaw = det : gResTab = tab : gResHash = hash : gResType = c\type
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

; Portable-tilstand: ligger der en portable.txt ved siden af exe-filen, gemmes
; indstillingerne dér i stedet for i %APPDATA%\Torrentry
Procedure.s ConfigDir()
  Protected exeDir.s = GetPathPart(ProgramFilename()), dir.s, old.s
  If FileSize(exeDir + "portable.txt") >= 0
    ProcedureReturn exeDir
  EndIf
  dir = GetEnvironmentVariable("APPDATA") + "\Torrentry\"
  ; foerste gang efter navneskiftet kopieres indstillingerne fra rTorrent Remote
  old = GetEnvironmentVariable("APPDATA") + "\rTorrentRemote\servers.ini"
  If FileSize(dir + "servers.ini") < 0 And FileSize(old) >= 0
    CreateDirectory(dir)
    CopyFile(old, dir + "servers.ini")
  EndIf
  ProcedureReturn dir
EndProcedure

Procedure LoadServers()
  Protected n.i, i.i, c.i
  ClearList(Servers())
  CurServer = 0
  If OpenPreferences(ConfigDir() + "servers.ini")
    PreferenceGroup("General")
    n = ReadPreferenceInteger("Count", 0)
    CurServer = ReadPreferenceInteger("Selected", 0)
    For i = 0 To n - 1
      PreferenceGroup("Server" + Str(i))
      AddElement(Servers())
      Servers()\name  = ReadPreferenceString("Name", "")
      Servers()\type  = Backend_TypeFromKey(ReadPreferenceString("Type", "rtorrent"))
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
  Protected i.i = 0, c.i, dir.s = ConfigDir()
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
      WritePreferenceString("Type", Backend_TypeKey(Servers()\type))
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
; Programikon (Sværm-T), indlejret som PNG-data i hex
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
    h16 = "89504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff61000002b24944415478da7d933b889c6514869feffbbf"
    h16 + "99d999d95ba2c23a6117b41321a56093222a31a085820111658985696295d82c281253087606636334a09d2816822145bc616527088a61"
    h16 + "251b272b264e92b9fdffff9d8bc5241b63e1db1dce7b9ec379e10470207072ddf789fbfe5a27d1c40291bb651053f4466a7923a40b1b1f"
    h16 + "86afc109006f1df6d30e47c643a12802cd7604fb0f20423d35549cee6222529ed93833f772d8787eb22fc6f637fdfe157a0f442d27ce5f"
    h16 + "978dc6dcddf3b9847bf644baddc01f9b5af47a2b58f8f3b154eae0e0e86acd7347ba7ae0d06201f0d13bd7e95fcab43b011ca653e7fed5"
    h16 + "06ebc79709c0f9cf6feaa7a787c5e22e0ea6c1d55256f6743870686967dbfab165fe4f4f3cb3c8b75f5ce7ca56293125e1e6a06216e64c"
    h16 + "e5c4d8be5cefd4db5b35e5f8dfa138370635210929b68cd1a8e6f5573679f1e80a836b35a7dee8a3e27cf2fdc3001c7be1228ef3ea9b3d"
    h16 + "76dfd7e4e353db0c8789d6bc91aaaaa23ddfe6d79f06bcf6d20d42844633b0b42bedec9b5f56febe26bc7d7c133768cdc1ee7b97a9aa4c"
    h16 + "32cbe45cd19e87ce028402a663c1ecce4966424ac2c252812bb843ce19b18a9455882193b3100220200a55a93b80e9b446c4a92b059f01"
    h16 + "a0896a269a64440535414c301326e392a27527b4664b998c4bec96474d30154432514d51ad51cda866b264446b4ebcb7770770e2fdbda8"
    h16 + "cf7ab77daa356a4a14af53d64cd68c5a66342c59e935587db08bb963eef4d6baf4d69a8c86256a336fad19f1dc8c4548e78247d4729125"
    h16 + "6ba3e5ba7971a0fd4b438d21680c41b7fb23fded9781a6966996ac6a12831b850ebf0a00cf3efadd07b81d16ab0821504e94b97662fde8"
    h16 + "4310e0ecbb3f339928ed4e81bb936213e2f0ec673f3cb51e6ebff3d38f9cdbaf5a3d6e56138a10a6e3ccd6ef130056d73ab4171ab8ba17"
    h16 + "b105a171e1cb1f9f3c0fce3f77649b10950cb5bf0000000049454e44ae426082"
    h48 = "89504e470d0a1a0a0000000d49484452000000300000003008060000005702f98700000bcf4944415478dac59a6b8c5dd575c77f7bef73"
    h48 + "eebd73efbcc7e347b101dbb8ae1fc4c14e08544d09a9914ad20a031aaab669434aa408f54b541289a41faee70b8984a89a0f518ada94b6"
    h48 + "494be2495a284dada6aa2a872490621b278609d8268e1ff8351ecff33ece397befd50fe7ce9d7b67ee98b9aea1475ad2dc39679fb5d75a"
    h48 + "ffb5d67fef7d14cbbe44158b28de836b78180125d7e5654343628686c4f01e5fcbd5bba4478bc5a2de3bbc5754cd13c54f4a0eaaab63ab"
    h48 + "f210e35c725da3614c2890412ba9f447b90b8f8da84a63e48787955fb6014343fbccc8c8430ee08b7f307b2fa83f12fc9d227e0d907d97"
    h48 + "9d1f2bf405a5f4cb08df7ce2d9c20b7311191951ee1d0d987bf0b1a1f3eb3341f7570393b957294de2aa789f20e251ef522a0882521aad"
    h48 + "0342d38120381bfd57c94efce95746d6bed9ca08d50c1bd1c3c3ca3f76ffb90f86b9ee1742935b558d276a0394aa3dff6e27b2a4222240"
    h48 + "2ed36b9c8baf54e2c93d7ff9dd1b5e6c44479301c5a2e8bdc3c8e34313eb44eb83468783892d252815f2ff7889781b9a7c20f829aff8e0"
    h48 + "93cff61e2f16bd9ecb09dd1c0e25b18ffe26341d83d564da0a842252f3c5bcccfdef7a4b2b1da082d896acd1d91e97549e2916bd5e04a1"
    h48 + "396cfdd9d0857b32a6ebfb5132ed9452660e384a4112837382311084aae69debe3e53970daabe810119bcbf406513475ff5ffcf3eae78a"
    h48 + "77fd77307ce06edb648d38ffe9748c88780f4a88234f69d6d1ddaf58b731a07785a6527644d5f4be788fc80241504af0dee3bd47a939af"
    h48 + "2e78ae414765d6d153d3d133a0a9941c71d4a003c18b1351fed300a32bc7a4160151a0a478d7c9dce440783cd0d9b5d6455e1ba5e3aad0"
    h48 + "bfd2b0e7533d6cb92d4b475e53ad08c78e463cffcc1417ce5af29d1aef248da5d4a29540b5e2c91752ff544a9e6c87260c6b1ead3dab8d"
    h48 + "a252f20cac0ed8f37037bff6fe1c1d7945b522bcf9b388e79e99e2d2db966c87c23b11a343657d7c39eb721b9efcd7c119415490360964"
    h48 + "7ca55aa3adacb22e06252a8e849e01cd67bf3448ffcaf98698cb2bdef7a11ceb37873cf9b94b9c792b269351f58939073d7d86df7bb487"
    h48 + "0f7cb880d2f0ea8fcabcf08d29ae8c394cd060682cacbe31e4b35f5a41df8a661d3bee48753cf5f94b8c5fb48419a59c8f0135e0b3c93a"
    h48 + "60746f1115cc0db2655dc884841e8756a8a8eab9ef937df4af34d8048260be66390b5dbd86871febe7c5fdb3e43a14e2416988aac29dbb"
    h48 + "3bd9746b96d36f55f00e7ef3e39dacbb25e487fb67c964e79fad56843b7717e85b6170168c99d76113e8ee333cf0480f5fdd3b4690d178"
    h48 + "11313aa3924a5200181d1d993740eb48bc64504a4812a167c0b075570e1152af35547f13a450d8b025cb862dad1bf30ff64ff0574f9c46"
    h48 + "bcf0c8e7d7b17bcf00eb3767972895351d2cd6b179478efe559a9989347a5e3c4ecf978fe624ae952e673d1d79c8e6745a8596a81cde81"
    h48 + "b3d22471e4714e78f54753f5dc38f462fa771cc9a2e7bd93b40ab578bf52e91cf2058db5bea1b4ce5fc182a60108da08d39396d28ca3a7"
    h48 + "2f8016468880368bd98809d2dfbfb567056ffcac8473c23d0fae401b45c6b06404161a3137cfd2ac63ea4a8236821741e3816469034404"
    h48 + "6d60ea4ac22b0766b8e7813e6c22f589017897fe3ef88359fe6364828e4e9de25aa5d567f7fdbddcfe912ebefc779b11117a07428efc78"
    h48 + "96fdfb26c8e6743a610de559cf47efebe1d77777e3aca0b56ac833210815877f38cbf8584c67775aed44fbd61188890924034a700e7279"
    h48 + "78eeef2fb37e738e5bb6752cf2f22f8f55f987af5c60ea8ac50469155280f770f2cd0a6b6eccb06e438af90b67639e7ee23ce592c798b4"
    h48 + "d72a951683f3a7ab0cae0ed9b4bd5947102a7e79bcca77be3e46369736b8b90e6ded5210c2a7b1ab79288e3c4f7de10cf73ed4cfaedfe8"
    h48 + "a2abd73033e1989ab03cff8dcb4c4d2474f5189c6ba8ed1a2a654fb5eceb3088ab42621d852ebda00f4069c6f2adaf5de4813f19a4bb2f"
    h48 + "a0a7df303be578f5a559f67f6b9c6ac5136674bde9895a0a42318899e32269829a005ce2d8f7d717f9b77fba4cbea0999e72ac5e9b61c7"
    h48 + "1d9d9c3a51218e1daa01c05e5257683d8febb94e6c9d6fca18e72093556cbab5836f3f7d9133bfa8d2d3175029a7ddbf23af094285733e"
    h48 + "7d578b246eaa425e7c5d048fab59ddd9a5113c33d30926102ebe5d25aa7a366ec911551dd030ae3e5e9af871e33d2f1ef0c49165fde62c"
    h48 + "ce79ce9dae108430339de0bda7b34ba394e07c3a17df34b6a501f162ae521b609d835a722b04e73caf1f9ae1e6cd39f29d6989a3699cb4"
    h48 + "a2c575413cd679b21d8a8d5b3b183d3c8b4d52ce945636c13a57377aa1d80608e906045d95ea7a498999f39e2084f3a72b4c8e276cde91"
    h48 + "278e1cd244b33dc882b556e3fb10e2aa63d3f63ca519cb999315820cb81af9f3e2df81762f012159c2e256a2b4f0faa169d6de9ca5bbdf"
    h48 + "60931416e97dd704a1c67783c75a4fa14773d3a61caf1d9a06e5dbd2dd1080d69df89dc47bc104307621e2c2db55b6ded64992344761e1"
    h48 + "22b1c9fb9163cbfb0b8c5f8cb870b64a1080f7ed2c7c5a1910c76d79c18bc704c26b87a6195c9361c5aa90247275de4f53124bddfb49ec"
    h48 + "e85b11b0665d8ea307a76b1db6cd08b4ca8176222022884f136e723ce2f48912db7675625d5a31447ceb2446b08967dbae4ece9d2a333e"
    h48 + "564d499b6f4f6f723d72406a491d6414af1f99a2bb37e0576ecc12551d020b9238fd471c3956de90616065c86b87a76ad0f16dea75806d"
    h48 + "4d258c645a69beea0688d6509af11c1f9d61dbce2ece9f29d79af9c2244e7367fbae2e7ef1e62cd31331b9bcc67b6973c7c537ceffff00"
    h48 + "a139eaed8530a378e3e83499ace6a65bf254abb6895d2a0551d5b2767d8e42a761f4c83441a6bdc46d94a521846f5fc483f24455cbe891"
    h48 + "49b6dcd6451034ef5888084ac3b69dddbc71749a4a2941e974d17f2d3aaf4f122f28ab614671e2e7338817366e295029cfc7b95276dcfc"
    h48 + "ab79825071ecb529c2ac4abdcfb5ee1fb562a3718c98367360c10a4a44f8c981313ef49141fa5764eaf77afa4276dcdecb4f0e8c619d27"
    h48 + "d4ea1af794a41681160624805950bfdb33401145968155ddecf9c43a7afac2fa24d7aceb60cf27d671f2d80ca74ecc1286414bbeb46c03"
    h48 + "d475861008958ae5a68d05fefca95beb939f5bd78a406777c0179edccea66d5d944b49caedaf515fd28a4a786f55bb7d40eaf4568823cb"
    h48 + "ef7f663db90e83b3b2a80a392704a1e60f1fdd8073bec6ed3dd7a673feed01c37b53254697bd7356291d08bec5327b69ecc7b1a77f30c3"
    h48 + "f69dbdb5c5fee2a1ba86fb2defeb6170759689f18820d4ede68212b1a2356580ad5b87440fb357008c9d382fe22ea174db1eb1ce91ef34"
    h48 + "e4f2c19266d7b7493a0c852ed3b04db2ec0e2c0a85133ba1abfeecdc61a006254343fbccc8cb0f553cbcac5528e2c5b58349a3617a32a2"
    h48 + "3c932ce95191542a25cbd4648436525ffc2c930339ad32829757460edd333534b4cf8012ddacc57f5dc42b2f5eb5c3874c00972f5538f4"
    h48 + "d2e5da6ec3623237b7ae3df23fe35c3c57260855fb3c089453f66f012e5d1a5400a6b6c728c5a2e8a7ff71d3f10d6b8ede9d09bad65b57"
    h48 + "b5e9de44f3c1432b99db2639fef3493efab1b5e40b01ce49ddeb2210049ad24cc2971f3f4c6926411bb5e850a3b5a4a73441900f623b73"
    h48 + "703a57f8dca9533773ead4a75c73199d4be6c43f92d8caa4d699c07b6b97d5899d27cc28ce9f2df1f8677eccf1d1498c514d72f2d8345f"
    h48 + "7cf4654ebd354d26a7f16e19f041f0de5aad83c0f9a88498870f1cb8db168b7baf7ec8f7f19dfff26113743caf75d097d892ad55735d3b"
    h48 + "9d544bf144631495b2259335ecbc63904d5b7b510a4ebc31c5e1972e5129bb7a74d4d58ec5d2987a10094d21f0626713173db0ffd07dff"
    h48 + "b9e421dfc233e28fddf6ec1613747f4debec5d88c7499cae75dfa1856a9df29c4ac9629daf1d626bf285006d54bae17bf58eae94321895"
    h48 + "01a5f12e7a29b2d547bf7fe4c19f2e9cfcb20eba7fe703df7bd08bfcb1c2dd2ef8554a05cbea0f5aab7a491561d9bc5fc409a831a5f42b"
    h48 + "c037bf77f077bf0d48abc95ffd53038a7a98e17a39f9eddbffbd5b27fe06c116dedd6355ca599173cffff4fec9a5e6d2e64717fb4cb1b8"
    h48 + "a0dcbe075711d169adbffac1ba6aeb731b50a34323efea49fdd691211966f99fdbfc2fb3375f1266797ab20000000049454e44ae426082"
    gIconSm  = IconFromHex(h16, 16)
    gIconBig = IconFromHex(h48, 48)
  EndIf
  If gIconSm  : SendMessage_(hwnd, #WM_SETICON, #ICON_SMALL, gIconSm)  : EndIf
  If gIconBig : SendMessage_(hwnd, #WM_SETICON, #ICON_BIG,   gIconBig) : EndIf
EndProcedure

Procedure ApplyServer()
  LockMutex(gMutex)
  If CurServer >= 0 And SelectElement(Servers(), CurServer)
    gConn\type = Servers()\type
    gConn\url = Servers()\url : gConn\user = Servers()\user : gConn\pass = Servers()\pass : gConn\noSSL = Servers()\noSSL
    SetWindowTitle(#Win, #APP_NAME + " - " + Servers()\name)
    StatusBarText(0, 0, "Forbinder til " + Servers()\name + " ...")
  Else
    gConn\type = #BT_RTorrent
    gConn\url = "" : gConn\user = "" : gConn\pass = "" : gConn\noSSL = 0
    SetWindowTitle(#Win, #APP_NAME)
    StatusBarText(0, 0, "Ingen server valgt - brug Server > Administrer servere...")
  EndIf
  gListRaw = "" : gDetRaw = ""
  gDetHash = ""
  UnlockMutex(gMutex)
  ClearList(Tor())
  RefreshList()
  UpdateGeneral()
  gRefresh = 1
EndProcedure

; Viser den valgte servers felter i serverdialogen
Procedure ShowServerFields()
  SetGadgetState(#G_SrvType, Servers()\type)
  SetGadgetText(#G_SrvUrlLbl, Backend_UrlHint(Servers()\type))
  SetGadgetText(#G_SrvName, Servers()\name) : SetGadgetText(#G_SrvUrl, Servers()\url)
  SetGadgetText(#G_SrvUser, Servers()\user) : SetGadgetText(#G_SrvPass, Servers()\pass)
  SetGadgetState(#G_SrvNoSSL, Servers()\noSSL)
EndProcedure

Procedure ServerDialog()
  Protected ev.i, quit.i, sel.i, url.s, type.i, i.i

  DisableWindow(#Win, #True)
  If OpenWindow(#WinSrv, 0, 0, 650, 350, "Servere", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#Win))
    ApplyIcon(WindowID(#WinSrv))
    ListViewGadget(#G_SrvList, 10, 10, 190, 330)
    TextGadget(#PB_Any, 215, 12, 200, 18, "Klient:")
    ComboBoxGadget(#G_SrvType, 215, 30, 420, 24)
    For i = 0 To #BT_Count - 1
      AddGadgetItem(#G_SrvType, -1, Backend_TypeName(i))
    Next
    SetGadgetState(#G_SrvType, #BT_RTorrent)
    TextGadget(#PB_Any, 215, 62, 200, 18, "Navn:")
    StringGadget(#G_SrvName, 215, 80, 420, 24, "")
    TextGadget(#G_SrvUrlLbl, 215, 110, 420, 18, Backend_UrlHint(#BT_RTorrent))
    StringGadget(#G_SrvUrl, 215, 128, 420, 24, "")
    TextGadget(#PB_Any, 215, 158, 200, 18, "Brugernavn:")
    StringGadget(#G_SrvUser, 215, 176, 420, 24, "")
    TextGadget(#PB_Any, 215, 206, 200, 18, "Adgangskode:")
    StringGadget(#G_SrvPass, 215, 224, 420, 24, "", #PB_String_Password)
    CheckBoxGadget(#G_SrvNoSSL, 215, 256, 420, 22, "Ignorer SSL-certifikatfejl")
    ButtonGadget(#G_SrvNew,   215, 300, 95, 28, "Ny")
    ButtonGadget(#G_SrvSave,  318, 300, 95, 28, "Gem")
    ButtonGadget(#G_SrvDel,   421, 300, 95, 28, "Slet")
    ButtonGadget(#G_SrvClose, 540, 300, 95, 28, "Luk")

    ForEach Servers() : AddGadgetItem(#G_SrvList, -1, Servers()\name) : Next
    If CurServer >= 0
      SetGadgetState(#G_SrvList, CurServer)
      SelectElement(Servers(), CurServer)
      ShowServerFields()
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
                ShowServerFields()
              EndIf
            Case #G_SrvType
              type = GetGadgetState(#G_SrvType)
              If type >= 0 : SetGadgetText(#G_SrvUrlLbl, Backend_UrlHint(type)) : EndIf
            Case #G_SrvNew
              SetGadgetState(#G_SrvList, -1)
              SetGadgetState(#G_SrvType, #BT_RTorrent)
              SetGadgetText(#G_SrvUrlLbl, Backend_UrlHint(#BT_RTorrent))
              SetGadgetText(#G_SrvName, "") : SetGadgetText(#G_SrvUrl, "https://")
              SetGadgetText(#G_SrvUser, "") : SetGadgetText(#G_SrvPass, "")
              SetGadgetState(#G_SrvNoSSL, 0)
            Case #G_SrvSave
              type = GetGadgetState(#G_SrvType)
              If type < 0 : type = #BT_RTorrent : EndIf
              url = Backend_NormalizeUrl(type, GetGadgetText(#G_SrvUrl))
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
                Servers()\type  = type
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
  Protected id.i, size.i, *buf, e.s
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
  e = Backend_AddFile(@gConn, *buf, size, start, dir)
  FreeMemory(*buf)
  If e <> ""
    MessageRequester(#APP_NAME, "Kunne ikke tilføje " + GetFilePart(path) + ":" + #LF$ + e, #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure AddMagnets(txt.s, start.i, dir.s)
  Protected i.i, n.i, ln.s, e.s, firstErr.s = ""
  txt = ReplaceString(txt, #CRLF$, #LF$)
  txt = ReplaceString(txt, #CR$, #LF$)
  n = CountString(txt, #LF$) + 1
  For i = 1 To n
    ln = Trim(StringField(txt, i, #LF$))
    If ln <> "" And (LCase(Left(ln, 7)) = "magnet:" Or LCase(Left(ln, 4)) = "http")
      e = Backend_AddUrl(@gConn, ln, start, dir)
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
  If gConn\url = "" : MessageRequester(#APP_NAME, "Vælg først en server.") : ProcedureReturn : EndIf
  f = OpenFileRequester("Vælg torrent-filer", "", "Torrent-filer (*.torrent)|*.torrent|Alle filer (*.*)|*.*", 0, #PB_Requester_MultiSelection)
  While f <> ""
    AddTorrentFile(f, #True, "")
    f = NextSelectedFileName()
  Wend
  gRefresh = 1
EndProcedure

Procedure MagnetDialog()
  Protected ev.i, quit.i, ok.i, txt.s, dir.s, start.i
  If gConn\url = "" : MessageRequester(#APP_NAME, "Vælg først en server.") : ProcedureReturn : EndIf
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

Procedure DoAction(act.i, all.i)
  Protected NewList h.s()
  Protected e.s
  If all
    ForEach Tor() : AddElement(h()) : h() = Tor()\hash : Next
  Else
    GetSelectedHashes(h())
  EndIf
  If ListSize(h()) = 0 : ProcedureReturn : EndIf
  e = Backend_Action(@gConn, act, h())
  If e <> "" : MessageRequester(#APP_NAME, "Fejl: " + e, #PB_MessageRequester_Error) : EndIf
  gRefresh = 1
EndProcedure

; withData = #False: fjern kun torrenten. #True: slet ogsaa filerne paa serveren (efter bekraeftelse)
Procedure RemoveSelected(withData.i)
  Protected NewList h.s()
  Protected info.s, shown.i = 0, e.s, warn.String
  GetSelectedHashes(h())
  If ListSize(h()) = 0 : ProcedureReturn : EndIf
  If withData = #False
    e = Backend_Remove(@gConn, h(), #False, @warn)
    If e <> "" : MessageRequester(#APP_NAME, e, #PB_MessageRequester_Error) : EndIf
    gRefresh = 1
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
    e = Backend_Remove(@gConn, h(), #True, @warn)
    gRefresh = 1
    If e <> ""
      MessageRequester(#APP_NAME, e, #PB_MessageRequester_Error)
    ElseIf warn\s <> ""
      MessageRequester(#APP_NAME, warn\s, #PB_MessageRequester_Warning)
    EndIf
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
  If gConn\url = ""
    MessageRequester(#APP_NAME, "Ingen server valgt.")
    ProcedureReturn
  EndIf
  MessageRequester(#APP_NAME + " - test af forbindelse", Backend_Test(@gConn))
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
    Case #M_Start      : DoAction(#Act_Start, #False)
    Case #M_Stop       : DoAction(#Act_Stop, #False)
    Case #M_StartAll   : DoAction(#Act_Start, #True)
    Case #M_StopAll    : DoAction(#Act_Stop, #True)
    Case #M_Recheck    : DoAction(#Act_Recheck, #False)
    Case #M_RemoveTorrent : RemoveSelected(#False)
    Case #M_RemoveData    : RemoveSelected(#True)
    Case #M_Servers    : ServerDialog()
    Case #M_Refresh    : gRefresh = 1
    Case #M_Test       : TestConnection()
    Case #M_Sidebar    : ToggleSidebar()
    Case #M_About
      MessageRequester("Om " + #APP_NAME, #APP_NAME + " - fjernbetjening til rTorrent, Transmission, qBittorrent og Deluge" + #LF$ + "Skrevet i PureBasic.")
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
  ; WindowHeight() regner menulinjen med, saa den skal ogsaa traekkes fra
  h = WindowHeight(#Win) - MenuHeight() - StatusBarHeight(0)
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
gInstMutex = CreateMutex_(0, 1, "Torrentry_SingleInstance_Mutex")
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
; UseIcon = torrentry.ico
; Executable = torrentry.exe
; IncludeVersionInfo
; VersionField0 = 1.0.0.0
; VersionField1 = 1.0