// WindowIdentity — resolve a live window's app identity (desktop-entry
// name + themed icon) from its window class, with honest fallbacks.
// Shared by the capture picker and the wizard's running-windows picker so
// both show "icon + app name + window title" identically. Never returns
// undefined: classes without a desktop entry fall back to the class
// string itself, and classes without any title fall back to the class.

.pragma library

function entry(DesktopEntries, cls) {
    try {
        var e = DesktopEntries.heuristicLookup(String(cls || ""))
        return e || null
    } catch (err) {
        return null
    }
}

function appName(DesktopEntries, cls, title) {
    var e = entry(DesktopEntries, cls)
    if (e && e.name && String(e.name).length > 0)
        return String(e.name)
    var t = String(title || "").trim()
    if (t.length > 0)
        return t.split(" ")[0].slice(0, 24)
    return String(cls || "").length > 0 ? String(cls) : "window"
}

function iconUrl(Quickshell, DesktopEntries, cls) {
    var e = entry(DesktopEntries, cls)
    if (e && e.icon && String(e.icon).length > 0)
        return Quickshell.iconPath(e.icon, true)
    return ""
}

function initial(cls, title) {
    var name = appName(null, cls, title)
    return name.length > 0 ? name.slice(0, 1).toUpperCase() : "?"
}
