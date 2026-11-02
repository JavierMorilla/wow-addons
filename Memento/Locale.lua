local _, ns = ...

local L = {
	Title = "Memento",
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
	Loaded = "is writing your story. Type |cffffd100/memento|r to open it.",
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
	L.Loaded = "está escribiendo tu historia. Escribe |cffffd100/memento|r para abrirla."
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
	L.Weekdays = { "domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado" }
	L.Months = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre" }
	function L.FormatDay(d)
		return format("%s, %d de %s de %d", L.Weekdays[d.wday], d.day, L.Months[d.month], d.year)
	end
end

ns.L = L
