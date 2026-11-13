# Embedded libraries

Unmodified copies of standard WoW addon libraries, embedded the usual way. LibStub loads the
newest copy when several addons embed the same library, so these are only used if nothing newer
is loaded.

| Library | Version | Upstream | Licence |
|---|---|---|---|
| LibStub | minor 2 | https://www.wowace.com/projects/libstub | Public domain |
| CallbackHandler-1.0 | minor 8 | https://www.wowace.com/projects/callbackhandler | BSD (see upstream) |
| LibDataBroker-1.1 | minor 4 | https://github.com/tekkub/libdatabroker-1-1 | Public domain (see upstream) |
| LibDBIcon-1.0 | minor 57 | https://www.curseforge.com/wow/addons/libdbicon-1-0 | See upstream |

Copied from the copies shipped with other addons on the WoW: Forever 1.60 client (Journalator).
LibDBIcon creates a button named `LibDBIcon10_UltimatePet`, which minimap button collectors such
as EllesmereUIMinimap recognise.
