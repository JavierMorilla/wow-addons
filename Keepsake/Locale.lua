local _, ns = ...

local L = {
	Title = "Keepsake",
	AllCharacters = "All characters",
	Search = "Search...",
	Import = "Import past achievements",
	Importing = "Importing... %d",
	Imported = "Imported %d achievements into the journal.",
	Screenshots = "Automatic screenshots",
	ScreenshotSaved = "Screenshot saved",
	Entries = "%d entries",
	Since = "since %s",
	Empty = "Nothing here yet. Go make some history.",
	Loaded = "is writing your story. Type |cffffd100/keepsake|r to open it.",
	Today = "Today",
	Yesterday = "Yesterday",
	-- filters
	All = "All",
	Levels = "Levels",
	Achievements = "Achievements",
	Bosses = "Bosses",
	Loot = "Loot",
	Collection = "Collection",
	Renown = "Renown",
	Zones = "Places",
	-- entries
	Started = "The journal begins",
	ReachedLevel = "Reached level %d",
	Points = "%d points",
	Defeated = "First victory: %s",
	MythicPlus = "+%d %s",
	InTime = "In time (+%d) · %s",
	Depleted = "Over time · %s",
	NewMount = "New mount",
	NewPet = "New pet",
	NewToy = "New toy",
	RenownLevel = "%s: renown %d",
	FirstVisit = "First visit",
	ItemLevel = "item level %d",
	Notes = "Notes",
	AddNote = "+ Note",
	NotePrompt = "Write a note for the journal:",
	EditNote = "Edit note",
	DeleteEntry = "Remove from the journal",
	Settings = "Settings",
	Scale = "Window size",
	MinimapButton = "Minimap button",
	LootFrom = "Record loot from",
	DateFormat = "%m/%d/%Y",
	RowHints = "Right-click: options",
	MinimapClick = "Click: open or close the journal",
	MinimapDrag = "Drag: move this button",
	MinimapRight = "Right-click: hide this button",
	MinimapHidden = "Minimap button hidden. Type |cffffd100/keepsake button|r to bring it back.",
	NoteUsage = "Type |cffffd100/keepsake note <text>|r to add a note.",
	NoteAdded = "Note added to the journal.",
	Weekdays = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" },
	Months = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
}

function L.FormatDay(d)
	return format("%s, %s %d, %d", L.Weekdays[d.wday], L.Months[d.month], d.day, d.year)
end

local locale = GetLocale()
if locale == "esES" or locale == "esMX" then
	L.AllCharacters = "Todos"
	L.Search = "Buscar..."
	L.Import = "Importar logros anteriores"
	L.Importing = "Importando... %d"
	L.Imported = "%d logros importados a la crónica."
	L.Screenshots = "Capturas automáticas"
	L.ScreenshotSaved = "Captura guardada"
	L.Entries = "%d hitos"
	L.Since = "desde %s"
	L.Empty = "Aún no hay nada aquí. Sal a escribir historia."
	L.Loaded = "está escribiendo tu historia. Escribe |cffffd100/keepsake|r para abrirla."
	L.Today = "Hoy"
	L.Yesterday = "Ayer"
	L.All = "Todo"
	L.Levels = "Niveles"
	L.Achievements = "Logros"
	L.Bosses = "Jefes"
	L.Loot = "Botín"
	L.Collection = "Colección"
	L.Renown = "Renombre"
	L.Zones = "Lugares"
	L.Started = "Comienza la crónica"
	L.ReachedLevel = "Alcanzas el nivel %d"
	L.Points = "%d puntos"
	L.Defeated = "Primera victoria: %s"
	L.InTime = "A tiempo (+%d) · %s"
	L.Depleted = "Fuera de tiempo · %s"
	L.NewMount = "Nueva montura"
	L.NewPet = "Nueva mascota"
	L.NewToy = "Nuevo juguete"
	L.RenownLevel = "%s: renombre %d"
	L.FirstVisit = "Primera visita"
	L.ItemLevel = "nivel de objeto %d"
	L.Notes = "Notas"
	L.AddNote = "+ Nota"
	L.NotePrompt = "Escribe una nota para la crónica:"
	L.EditNote = "Editar nota"
	L.DeleteEntry = "Quitar de la crónica"
	L.Settings = "Ajustes"
	L.Scale = "Tamaño de la ventana"
	L.MinimapButton = "Botón del minimapa"
	L.LootFrom = "Registrar botín desde"
	L.DateFormat = "%d/%m/%Y"
	L.RowHints = "Clic derecho: opciones"
	L.MinimapClick = "Clic: abrir o cerrar la crónica"
	L.MinimapDrag = "Arrastrar: mover este botón"
	L.MinimapRight = "Clic derecho: ocultar este botón"
	L.MinimapHidden = "Botón del minimapa oculto. Escribe |cffffd100/keepsake boton|r para recuperarlo."
	L.NoteUsage = "Escribe |cffffd100/keepsake nota <texto>|r para añadir una nota."
	L.NoteAdded = "Nota añadida a la crónica."
	L.Weekdays = { "domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado" }
	L.Months = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre" }
	function L.FormatDay(d)
		return format("%s, %d de %s de %d", L.Weekdays[d.wday], d.day, L.Months[d.month], d.year)
	end
end

ns.L = L
