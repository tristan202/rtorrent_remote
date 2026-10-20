;==============================================================================
; Backend-lag: faelles typer og procedurer, som UI'et bruger uanset klient.
; Hver klient implementeres i sin egen backend_*.pbi, og Backend_* vaelger
; den rigtige ud fra Conn\type.
;==============================================================================

Enumeration
  #BT_RTorrent
  #BT_Transmission
  #BT_QBittorrent
  #BT_Deluge
  #BT_Count         ; antal klienttyper
EndEnumeration

Enumeration
  #Act_Start
  #Act_Stop
  #Act_Recheck
EndEnumeration

; Forbindelsesoplysninger for den aktive server
Structure Conn
  type.i
  url.s
  user.s
  pass.s
  noSSL.i
EndStructure

; Status-felterne (state/complete/active/hashing) foelger rTorrents betydning;
; andre backends saetter dem, saa ComputeTorrent giver den rigtige status.
Structure Torrent
  hash.s
  name.s
  size.q
  done.q
  leftB.q
  downRate.q
  upRate.q
  ratio.q         ; i tusindedele (1000 = 1.00)
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

Structure TrackerInfo
  url.s
  enabled.i
  seeds.i
  peers.i
  downloads.i
EndStructure

Structure PeerInfo
  ip.s
  port.i
  client.s
  progress.d      ; procent
  downRate.q
  upRate.q
EndStructure

Structure FileInfo
  path.s
  size.q
  progress.d      ; procent
  priority.i      ; 0 = spring over, 1 = normal, 2 = hoej
EndStructure

;------------------------------------------------------------------------------
; Faelles hjaelpere
;------------------------------------------------------------------------------
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

; Udleder forloeb, ETA og statustekst ud fra de raa felter
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
EndProcedure

XIncludeFile "backend_rtorrent.pbi"
XIncludeFile "backend_transmission.pbi"
XIncludeFile "backend_qbittorrent.pbi"
XIncludeFile "backend_deluge.pbi"

;------------------------------------------------------------------------------
; Klienttyper
;------------------------------------------------------------------------------
; Navnet der gemmes som "Type" i servers.ini
Procedure.s Backend_TypeKey(type.i)
  Select type
    Case #BT_RTorrent     : ProcedureReturn "rtorrent"
    Case #BT_Transmission : ProcedureReturn "transmission"
    Case #BT_QBittorrent  : ProcedureReturn "qbittorrent"
    Case #BT_Deluge       : ProcedureReturn "deluge"
  EndSelect
  ProcedureReturn "rtorrent"
EndProcedure

Procedure.i Backend_TypeFromKey(key.s)
  Select LCase(Trim(key))
    Case "rtorrent"     : ProcedureReturn #BT_RTorrent
    Case "transmission" : ProcedureReturn #BT_Transmission
    Case "qbittorrent"  : ProcedureReturn #BT_QBittorrent
    Case "deluge"       : ProcedureReturn #BT_Deluge
  EndSelect
  ProcedureReturn #BT_RTorrent
EndProcedure

; Navnet der vises i serverdialogen
Procedure.s Backend_TypeName(type.i)
  Select type
    Case #BT_RTorrent     : ProcedureReturn "rTorrent (XML-RPC)"
    Case #BT_Transmission : ProcedureReturn "Transmission"
    Case #BT_QBittorrent  : ProcedureReturn "qBittorrent"
    Case #BT_Deluge       : ProcedureReturn "Deluge (Web UI)"
  EndSelect
  ProcedureReturn ""
EndProcedure

; Hjaelpetekst over URL-feltet i serverdialogen
Procedure.s Backend_UrlHint(type.i)
  Select type
    Case #BT_Transmission : ProcedureReturn "URL (f.eks. https://bruger.server.usbx.me/transmission/rpc):"
    Case #BT_QBittorrent  : ProcedureReturn "URL (f.eks. https://bruger.server.usbx.me/qbittorrent):"
    Case #BT_Deluge       : ProcedureReturn "URL (f.eks. https://bruger.server.usbx.me/deluge) - kun adgangskode:"
  EndSelect
  ProcedureReturn "URL (f.eks. https://bruger.server.usbx.me/RPC2):"
EndProcedure

Procedure.s Backend_NormalizeUrl(type.i, url.s)
  Select type
    Case #BT_RTorrent : ProcedureReturn RT_NormalizeUrl(url)
    Case #BT_Transmission : ProcedureReturn TR_NormalizeUrl(url)
    Case #BT_QBittorrent  : ProcedureReturn QB_NormalizeUrl(url)
    Case #BT_Deluge       : ProcedureReturn DL_NormalizeUrl(url)
  EndSelect
  ProcedureReturn Trim(url)
EndProcedure

;------------------------------------------------------------------------------
; Torrent-liste og detaljer. Fetch* kaldes fra poll-traaden og returnerer et
; raat svar, som kun backenden selv forstaar; Parse* og *Error kaldes fra
; hovedtraaden.
;------------------------------------------------------------------------------
Procedure.s Backend_FetchList(*c.Conn)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_FetchList(*c)
    Case #BT_Transmission : ProcedureReturn TR_FetchList(*c)
    Case #BT_QBittorrent  : ProcedureReturn QB_FetchList(*c)
    Case #BT_Deluge       : ProcedureReturn DL_FetchList(*c)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s Backend_ListError(type.i, raw.s)
  Select type
    Case #BT_RTorrent : ProcedureReturn RT_ListError(raw)
    Case #BT_Transmission : ProcedureReturn TR_ListError(raw)
    Case #BT_QBittorrent  : ProcedureReturn QB_ListError(raw)
    Case #BT_Deluge       : ProcedureReturn DL_ListError(raw)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure Backend_ParseList(type.i, raw.s, List t.Torrent())
  Select type
    Case #BT_RTorrent : RT_ParseList(raw, t())
    Case #BT_Transmission : TR_ParseList(raw, t())
    Case #BT_QBittorrent  : QB_ParseList(raw, t())
    Case #BT_Deluge       : DL_ParseList(raw, t())
  EndSelect
EndProcedure

Procedure.s Backend_FetchDetails(*c.Conn, tab.i, hash.s)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_FetchDetails(*c, tab, hash)
    Case #BT_Transmission : ProcedureReturn TR_FetchDetails(*c, tab, hash)
    Case #BT_QBittorrent  : ProcedureReturn QB_FetchDetails(*c, tab, hash)
    Case #BT_Deluge       : ProcedureReturn DL_FetchDetails(*c, tab, hash)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s Backend_DetailsError(type.i, raw.s)
  Select type
    Case #BT_RTorrent : ProcedureReturn RT_Error(raw)
    Case #BT_Transmission : ProcedureReturn TR_Error(raw)
    Case #BT_QBittorrent  : ProcedureReturn QB_Error(raw)
    Case #BT_Deluge       : ProcedureReturn DL_Error(raw)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure Backend_ParseTrackers(type.i, raw.s, List x.TrackerInfo())
  Select type
    Case #BT_RTorrent : RT_ParseTrackers(raw, x())
    Case #BT_Transmission : TR_ParseTrackers(raw, x())
    Case #BT_QBittorrent  : QB_ParseTrackers(raw, x())
    Case #BT_Deluge       : DL_ParseTrackers(raw, x())
  EndSelect
EndProcedure

Procedure Backend_ParsePeers(type.i, raw.s, List x.PeerInfo())
  Select type
    Case #BT_RTorrent : RT_ParsePeers(raw, x())
    Case #BT_Transmission : TR_ParsePeers(raw, x())
    Case #BT_QBittorrent  : QB_ParsePeers(raw, x())
    Case #BT_Deluge       : DL_ParsePeers(raw, x())
  EndSelect
EndProcedure

Procedure Backend_ParseFiles(type.i, raw.s, List x.FileInfo())
  Select type
    Case #BT_RTorrent : RT_ParseFiles(raw, x())
    Case #BT_Transmission : TR_ParseFiles(raw, x())
    Case #BT_QBittorrent  : QB_ParseFiles(raw, x())
    Case #BT_Deluge       : DL_ParseFiles(raw, x())
  EndSelect
EndProcedure

;------------------------------------------------------------------------------
; Kommandoer. Returnerer en fejltekst, eller "" hvis alt gik godt.
;------------------------------------------------------------------------------
Procedure.s Backend_Action(*c.Conn, act.i, List h.s())
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_Action(*c, act, h())
    Case #BT_Transmission : ProcedureReturn TR_Action(*c, act, h())
    Case #BT_QBittorrent  : ProcedureReturn QB_Action(*c, act, h())
    Case #BT_Deluge       : ProcedureReturn DL_Action(*c, act, h())
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s Backend_Remove(*c.Conn, List h.s(), withData.i, *warn.String)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_Remove(*c, h(), withData, *warn)
    Case #BT_Transmission : ProcedureReturn TR_Remove(*c, h(), withData, *warn)
    Case #BT_QBittorrent  : ProcedureReturn QB_Remove(*c, h(), withData, *warn)
    Case #BT_Deluge       : ProcedureReturn DL_Remove(*c, h(), withData, *warn)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s Backend_AddFile(*c.Conn, *buf, size.i, start.i, dir.s)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_AddFile(*c, *buf, size, start, dir)
    Case #BT_Transmission : ProcedureReturn TR_AddFile(*c, *buf, size, start, dir)
    Case #BT_QBittorrent  : ProcedureReturn QB_AddFile(*c, *buf, size, start, dir)
    Case #BT_Deluge       : ProcedureReturn DL_AddFile(*c, *buf, size, start, dir)
  EndSelect
  ProcedureReturn ""
EndProcedure

Procedure.s Backend_AddUrl(*c.Conn, url.s, start.i, dir.s)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_AddUrl(*c, url, start, dir)
    Case #BT_Transmission : ProcedureReturn TR_AddUrl(*c, url, start, dir)
    Case #BT_QBittorrent  : ProcedureReturn QB_AddUrl(*c, url, start, dir)
    Case #BT_Deluge       : ProcedureReturn DL_AddUrl(*c, url, start, dir)
  EndSelect
  ProcedureReturn ""
EndProcedure

; Teksten der vises under Server > Test forbindelse
Procedure.s Backend_Test(*c.Conn)
  Select *c\type
    Case #BT_RTorrent : ProcedureReturn RT_Test(*c)
    Case #BT_Transmission : ProcedureReturn TR_Test(*c)
    Case #BT_QBittorrent  : ProcedureReturn QB_Test(*c)
    Case #BT_Deluge       : ProcedureReturn DL_Test(*c)
  EndSelect
  ProcedureReturn ""
EndProcedure
