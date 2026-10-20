;==============================================================================
; Oversaettelser. Sprogfilerne (DA.lng, EN.lng ...) ligger ved siden af exe-filen
; og er ini-filer med en [Language]-gruppe, samme format som i AI Copilot Mapper.
; Dansk er indbygget (DataSection nederst), saa en manglende noegle eller fil
; aldrig giver tom tekst. Valget gemmes som Language i servers.ini [View].
;==============================================================================

Import "Kernel32.lib"
  GetUserDefaultUILanguage.w()
EndImport

CompilerIf Not Defined(LOCALE_SISO639LANGNAME, #PB_Constant)
  #LOCALE_SISO639LANGNAME = $59
CompilerEndIf

Structure LangInfo
  code.s
  name.s
EndStructure

Global NewList Languages.LangInfo()
Global NewMap gTxt.s()
Global gTxtMutex = CreateMutex()
Global gLanguage.s = ""

; Slaar en tekst op og saetter p1 ind i stedet for %1. Kaldes ogsaa fra polle-traaden,
; derfor mutexen
Procedure.s Lng(key.s, p1.s = "")
  Protected r.s
  LockMutex(gTxtMutex)
  If FindMapElement(gTxt(), key)
    r = gTxt()
  Else
    r = key
  EndIf
  UnlockMutex(gTxtMutex)
  ProcedureReturn ReplaceString(r, "%1", p1)
EndProcedure

; Menutekst uden "..." til brug inde i en anden tekst
Procedure.s NoDots(s.s)
  If Right(s, 3) = "..." : s = Left(s, Len(s) - 3) : EndIf
  ProcedureReturn s
EndProcedure

Procedure.i LanguageExists(code.s)
  ForEach Languages()
    If Languages()\code = UCase(code) : ProcedureReturn #True : EndIf
  Next
  ProcedureReturn #False
EndProcedure

; Finder *.lng ved siden af exe-filen. Dansk er altid med, ogsaa uden DA.lng
Procedure ScanLanguages()
  Protected dir.s = GetPathPart(ProgramFilename()), d.i, fn.s, code.s
  ClearList(Languages())
  AddElement(Languages())
  Languages()\code = "DA"
  Languages()\name = "Dansk"
  d = ExamineDirectory(#PB_Any, dir, "*.lng")
  If d
    While NextDirectoryEntry(d)
      If DirectoryEntryType(d) = #PB_DirectoryEntry_File
        fn = DirectoryEntryName(d)
        code = UCase(GetFilePart(fn, #PB_FileSystem_NoExtension))
        If code <> "DA" And LanguageExists(code) = #False And OpenPreferences(dir + fn)
          PreferenceGroup("Language")
          AddElement(Languages())
          Languages()\code = code
          Languages()\name = ReadPreferenceString("LanguageName", code)
          ClosePreferences()
        EndIf
      EndIf
    Wend
    FinishDirectory(d)
  EndIf
  SortStructuredList(Languages(), #PB_Sort_Ascending | #PB_Sort_NoCase, OffsetOf(LangInfo\name), #PB_String)
EndProcedure

; Windows' visningssprog, hvis der er en sprogfil til det - ellers engelsk
Procedure.s DetectLanguage()
  Protected buf.s = Space(16), code.s
  If GetLocaleInfo_(GetUserDefaultUILanguage(), #LOCALE_SISO639LANGNAME, @buf, 16) > 0
    code = UCase(Trim(buf))
    If LanguageExists(code) : ProcedureReturn code : EndIf
  EndIf
  If LanguageExists("EN") : ProcedureReturn "EN" : EndIf
  ProcedureReturn "DA"
EndProcedure

; Indlaeser de danske standardtekster og laegger sprogfilens tekster ovenpaa
Procedure LoadLanguage(code.s)
  Protected key.s, value.s, file.s
  code = UCase(code)
  If LanguageExists(code) = #False : code = "DA" : EndIf
  file = GetPathPart(ProgramFilename()) + code + ".lng"
  LockMutex(gTxtMutex)
  ClearMap(gTxt())
  Restore LangDefaults
  Repeat
    Read.s key
    If key = "" : Break : EndIf
    Read.s value
    gTxt(key) = value
  ForEver
  If FileSize(file) > 0 And OpenPreferences(file)
    If PreferenceGroup("Language")
      ExaminePreferenceKeys()
      While NextPreferenceKey()
        gTxt(PreferenceKeyName()) = ReplaceString(PreferenceKeyValue(), "\n", #LF$)
      Wend
    EndIf
    ClosePreferences()
  EndIf
  gLanguage = code
  UnlockMutex(gTxtMutex)
EndProcedure

; Danske standardtekster - skal svare til DA.lng
DataSection
  LangDefaults:
  Data.s "LanguageName", "Dansk"
  Data.s "UnitDay", "d"
  Data.s "UnitHour", "t"
  Data.s "FltAll", "Alle"
  Data.s "FltDownloading", "Henter"
  Data.s "FltSeeding", "Seeder"
  Data.s "FltCompleted", "Færdige"
  Data.s "FltStopped", "Stoppede"
  Data.s "FltActive", "Aktive"
  Data.s "FltInactive", "Inaktive"
  Data.s "FltError", "Fejl"
  Data.s "StDownloading", "Henter"
  Data.s "StSeeding", "Seeder"
  Data.s "StChecking", "Tjekker"
  Data.s "StFinished", "Færdig"
  Data.s "StStopped", "Stoppet"
  Data.s "StPaused", "Pause"
  Data.s "StQueued", "I kø"
  Data.s "StMoving", "Flytter"
  Data.s "StAllocating", "Allokerer"
  Data.s "StError", "Fejl"
  Data.s "StMetadata", "Henter metadata"
  Data.s "ColName", "Navn"
  Data.s "ColSize", "Størrelse"
  Data.s "ColProgress", "Forløb"
  Data.s "ColStatus", "Status"
  Data.s "ColSeeds", "Seeds"
  Data.s "ColPeers", "Peers"
  Data.s "ColDownSpeed", "Down-hastighed"
  Data.s "ColUpSpeed", "Up-hastighed"
  Data.s "ColEta", "ETA"
  Data.s "ColSeedTime", "Seedtid"
  Data.s "ColRatio", "Ratio"
  Data.s "ColLabel", "Label"
  Data.s "ColProperty", "Egenskab"
  Data.s "ColValue", "Værdi"
  Data.s "ColDownloads", "Downloads"
  Data.s "ColPort", "Port"
  Data.s "ColClient", "Klient"
  Data.s "ColDown", "Down"
  Data.s "ColUp", "Up"
  Data.s "ColPath", "Sti"
  Data.s "ColPriority", "Prioritet"
  Data.s "TabGeneral", "Generelt"
  Data.s "TabTrackers", "Trackere"
  Data.s "TabPeers", "Peers"
  Data.s "TabContent", "Indhold"
  Data.s "GenSavedIn", "Gemmes i"
  Data.s "GenDownloaded", "Hentet"
  Data.s "GenUpTotal", "Uploadet i alt"
  Data.s "GenDownTotal", "Downloadet i alt"
  Data.s "GenMessage", "Besked"
  Data.s "GenSeededFor", "Seedet i"
  Data.s "TrkEnabled", "Aktiv"
  Data.s "TrkDisabled", "Deaktiveret"
  Data.s "PrioSkip", "Spring over"
  Data.s "PrioNormal", "Normal"
  Data.s "PrioHigh", "Høj"
  Data.s "MenuFile", "Fil"
  Data.s "MenuAddFile", "Tilføj torrent-fil..."
  Data.s "MenuAddMagnet", "Tilføj magnet-link..."
  Data.s "MenuQuit", "Afslut"
  Data.s "MenuTorrent", "Torrent"
  Data.s "MenuStart", "Start"
  Data.s "MenuStop", "Stop"
  Data.s "MenuStartAll", "Start alle"
  Data.s "MenuStopAll", "Stop alle"
  Data.s "MenuRecheck", "Gentjek hash"
  Data.s "MenuRemove", "Fjern"
  Data.s "MenuDelTorrent", "Slet torrent"
  Data.s "MenuDelData", "Slet torrent + data..."
  Data.s "MenuServer", "Server"
  Data.s "MenuServers", "Administrer servere..."
  Data.s "MenuRefresh", "Opdater nu"
  Data.s "MenuTest", "Test forbindelse..."
  Data.s "MenuView", "Vis"
  Data.s "MenuSidebar", "Sidebjælke"
  Data.s "MenuLanguage", "Sprog"
  Data.s "MenuHelp", "Hjælp"
  Data.s "MenuAbout", "Om..."
  Data.s "TipAddFile", "Tilføj torrent-fil"
  Data.s "TipAddMagnet", "Tilføj magnet-link"
  Data.s "TipStart", "Start valgte torrents"
  Data.s "TipStop", "Stop valgte torrents"
  Data.s "TipRemove", "Fjern valgte torrents"
  Data.s "TipServer", "Aktiv server"
  Data.s "LblSearch", "Søg:"
  Data.s "LblError", "Fejl"
  Data.s "MsgListFailed", "Kunne ikke hente listen:"
  Data.s "MsgSeeDetails", "Brug %1 for flere detaljer."
  Data.s "StatusConnected", "Forbundet: %1"
  Data.s "StatusTorrents", "%1 torrents"
  Data.s "StatusConnecting", "Forbinder til %1 ..."
  Data.s "StatusNoServer", "Ingen server valgt - brug %1"
  Data.s "MsgNoServer", "Ingen server valgt."
  Data.s "MsgSelectServer", "Vælg først en server."
  Data.s "SrvTitle", "Servere"
  Data.s "SrvClient", "Klient:"
  Data.s "SrvName", "Navn:"
  Data.s "SrvUser", "Brugernavn:"
  Data.s "SrvPass", "Adgangskode:"
  Data.s "SrvNoSSL", "Ignorer SSL-certifikatfejl"
  Data.s "BtnNew", "Ny"
  Data.s "BtnSave", "Gem"
  Data.s "BtnDelete", "Slet"
  Data.s "BtnClose", "Luk"
  Data.s "BtnAdd", "Tilføj"
  Data.s "BtnCancel", "Annuller"
  Data.s "MsgFillNameUrl", "Udfyld mindst navn og URL."
  Data.s "UrlHint", "URL (f.eks. %1):"
  Data.s "UrlHintPassOnly", "URL (f.eks. %1) - kun adgangskode:"
  Data.s "ExampleUser", "bruger"
  Data.s "MsgCantOpen", "Kan ikke åbne filen:"
  Data.s "MsgBadSize", "Ugyldig filstørrelse: %1"
  Data.s "MsgCouldNotAdd", "Kunne ikke tilføje %1:"
  Data.s "MsgAddError", "Fejl ved tilføjelse: %1"
  Data.s "DlgSelectFiles", "Vælg torrent-filer"
  Data.s "FilterTorrents", "Torrent-filer"
  Data.s "FilterAll", "Alle filer"
  Data.s "MagTitle", "Tilføj magnet-links"
  Data.s "MagLinks", "Magnet-links (ét pr. linje):"
  Data.s "MagDir", "Gem i mappe på serveren (valgfrit):"
  Data.s "MagStart", "Start straks"
  Data.s "DelConfirm", "Slet %1 torrent(s) og deres filer på serveren?"
  Data.s "DelMore", "... og %1 mere"
  Data.s "DelPermanent", "Filerne slettes permanent og kan ikke fortrydes."
  Data.s "TestTitle", "test af forbindelse"
  Data.s "AboutTitle", "Om %1"
  Data.s "AboutText", "%1 - fjernbetjening til rTorrent, Transmission, qBittorrent og Deluge"
  Data.s "AboutWritten", "Skrevet i PureBasic."
  Data.s "ErrConnect", "Kunne ikke forbinde til serveren"
  Data.s "ErrBadLogin", "forkert brugernavn/adgangskode"
  Data.s "ErrCheckUrl", "tjek URL (normalt %1)"
  Data.s "ErrAtLogin", "ved login"
  Data.s "ErrInvalidResponse", "Ugyldigt svar fra %1"
  Data.s "ErrUnknownFrom", "Ukendt fejl fra %1"
  Data.s "ErrNotRemoved", "%1 torrent(s) kunne ikke fjernes"
  Data.s "ErrDLProxyAuth", "serveren kræver login foran Deluge"
  Data.s "ErrDLBadPass", "Login afvist - forkert adgangskode"
  Data.s "ErrDLNoDaemon", "Deluge Web UI kender ingen daemon at forbinde til"
  Data.s "ErrDLDaemon", "Kunne ikke forbinde Web UI til daemon: %1"
  Data.s "ErrQBBadLogin", "Login afvist - forkert brugernavn/adgangskode"
  Data.s "ErrQBBanned", "Login blokeret af qBittorrent (for mange forkerte forsøg)"
  Data.s "ErrQB404", "ukendt API-kald eller torrent"
  Data.s "ErrQBRejected", "qBittorrent afviste kaldet"
  Data.s "MsgTorrentError", "Fejl i torrenten"
  Data.s "MsgFilesMissing", "Filerne mangler på serveren"
  Data.s "ErrRTUnknown", "Ukendt XML-RPC-fejl"
  Data.s "ErrRTNoPath", "Kunne ikke finde filernes placering:"
  Data.s "ErrRTBadPath", "Serveren gav uventede svar om filernes placering."
  Data.s "MsgNothingDeleted", "Intet er slettet."
  Data.s "WarnRTRmFailed", "Serveren afviste sletning af filer:"
  Data.s "WarnRTLeftBehind", "Torrenten er fjernet, men filerne kan ligge tilbage."
  Data.s "WarnRTSkipped", "%1 torrent(s) fik ikke slettet filer, fordi stien ikke kunne bekræftes som sikker."
  Data.s "WarnRTRemovedAnyway", "Selve torrenterne er fjernet."
  Data.s "ErrTR409", "serveren gav ingen gyldig session-id"
  Data.s "TestUser", "Bruger"
  Data.s "TestFailed", "%1 fejlede:"
  Data.s "TestDefaultDir", "Standardmappe"
  Data.s "TestRpcVersion", "RPC-version"
  Data.s "TestChars", "%1 tegn"
  Data.s ""
EndDataSection
