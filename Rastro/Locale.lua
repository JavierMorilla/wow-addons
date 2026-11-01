local _, ns = ...

local L = {
	Title = "Trail",
	Missing = "%d to collect here",
	NothingMissing = "You have everything this place offers.",
	Scanning = "Reading the collections...",
	Mounts = "Mounts",
	Pets = "Pets",
	WildPets = "Wild pets (pet battle)",
	InstanceLoot = "%s · %s",
	Entrances = "Dungeons and raids in this zone",
	EntranceMissing = "click to see what you are missing",
	Back = "Back",
	Killed = "killed",
	Mount = "mount",
	Pet = "pet",
	Toy = "toy",
	Appearance = "appearance",
	Wild = "wild",
	PillMounts = "%d |4mount:mounts;",
	PillPets = "%d |4pet:pets;",
	PillLoot = "%d |4item:items;",
	Busy = "Close the Adventure Guide to read this instance's loot.",
	Loading = "Loading item data...",
	Hints = "Click: open in collections · Ctrl-click: preview · Shift-click: link",
	Loaded = "follows the trail. Type |cffffd100/rastro|r or click the pill under the minimap.",
	ShowPill = "Show the pill",
	PillDrag = "Click: open · Shift-drag: move",
	SameNameNote = "Matched by zone name in the item's source text.",
}

local locale = GetLocale()
if locale == "esES" or locale == "esMX" then
	L.Title = "Rastro"
	L.Missing = "Te faltan %d cosas aquí"
	L.NothingMissing = "Ya tienes todo lo que ofrece este lugar."
	L.Scanning = "Leyendo las colecciones..."
	L.Mounts = "Monturas"
	L.Pets = "Mascotas"
	L.WildPets = "Mascotas salvajes (duelo de mascotas)"
	L.Entrances = "Mazmorras y bandas de esta zona"
	L.EntranceMissing = "clic para ver lo que te falta"
	L.Back = "Volver"
	L.Killed = "muerto"
	L.Mount = "montura"
	L.Pet = "mascota"
	L.Toy = "juguete"
	L.Appearance = "apariencia"
	L.Wild = "salvaje"
	L.PillMounts = "%d |4montura:monturas;"
	L.PillPets = "%d |4mascota:mascotas;"
	L.PillLoot = "%d |4objeto:objetos;"
	L.Busy = "Cierra la Guía de aventuras para leer el botín de esta instancia."
	L.Loading = "Cargando datos de objetos..."
	L.Hints = "Clic: abrir en colecciones · Ctrl+clic: probar · Mayús+clic: enlazar"
	L.Loaded = "sigue el rastro. Escribe |cffffd100/rastro|r o pulsa la pastilla bajo el minimapa."
	L.ShowPill = "Mostrar la pastilla"
	L.PillDrag = "Clic: abrir · Mayús+arrastrar: mover"
	L.SameNameNote = "Encontrado por el nombre de la zona en el origen del objeto."
end

ns.L = L
