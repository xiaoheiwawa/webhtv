import Foundation

// MARK: - Class (category)

/// A video category (`class` array), mirroring Android `com.fongmi.android.tv.bean.Class`.
struct VodClass: Equatable {
    var typeId: String
    var typeName: String
    var filter: Bool = false

    init(typeId: String, typeName: String, filter: Bool = false) {
        self.typeId = typeId
        self.typeName = typeName
        self.filter = filter
    }

    static func from(dict: [String: Any]) -> VodClass? {
        let id = (dict["type_id"] as? String) ?? (dict["id"] as? String) ?? ""
        let name = (dict["type_name"] as? String) ?? (dict["name"] as? String) ?? ""
        guard !id.isEmpty else { return nil }
        let filter = (dict["filter"] as? Bool) ?? ((dict["filter"] as? String) == "1")
        return VodClass(typeId: id, typeName: name, filter: filter)
    }
}

// MARK: - Episode / Flag

/// A single episode inside a play flag (`episodes` / `$$$`-separated play_urls).
struct Episode: Equatable {
    var name: String
    var desc: String
    var url: String

    init(name: String, desc: String, url: String) {
        self.name = name
        self.desc = desc
        self.url = url
    }
}

/// A playback source group (`vod_play_from` / `vod_flags`), mirroring Android `Flag`.
struct Flag: Equatable {
    var flag: String
    var show: String
    var url: String
    var episodes: [Episode]

    init(flag: String, show: String, url: String, episodes: [Episode]) {
        self.flag = flag
        self.show = show
        self.url = url
        self.episodes = episodes
    }

    mutating func buildEpisodes() {
        if !episodes.isEmpty { return }
        var list: [Episode] = []
        let parts = url.contains("#") ? url.components(separatedBy: "#") : (url.isEmpty ? [] : [url])
        for (i, part) in parts.enumerated() {
            let pair = part.components(separatedBy: "$").filter { !$0.isEmpty }
            let number = String(format: "%02d", i + 1)
            if pair.count >= 2 {
                list.append(Episode(name: (pair[0].isEmpty ? number : pair[0]), desc: "", url: pair[1]))
            } else if pair.count == 1 {
                list.append(Episode(name: number, desc: "", url: pair[0]))
            }
        }
        episodes = list
    }

    static func from(dict: [String: Any]) -> Flag? {
        let flag = (dict["flag"] as? String) ?? ""
        let urls = (dict["urls"] as? String) ?? ""
        guard !flag.isEmpty else { return nil }
        var eps: [Episode] = []
        if let arr = dict["episodes"] as? [Any] {
            for e in arr {
                if let ed = e as? [String: Any] {
                    eps.append(Episode(
                        name: (ed["name"] as? String) ?? "",
                        desc: (ed["desc"] as? String) ?? "",
                        url: (ed["url"] as? String) ?? ""))
                }
            }
        }
        return Flag(flag: flag, show: (dict["show"] as? String) ?? flag, url: urls, episodes: eps)
    }
}

// MARK: - Vod

/// A single video entry, mirroring Android `Vod`.
struct Vod: Equatable {
    var vodId: String
    var vodName: String
    var typeName: String
    var vodPic: String
    var vodRemarks: String
    var vodYear: String
    var vodArea: String
    var vodDirector: String
    var vodActor: String
    var vodContent: String
    var vodPlayFrom: String
    var vodPlayUrl: String
    var vodTag: String
    var action: String
    var flags: [Flag]

    init(dict: [String: Any]) {
        func str(_ k: String) -> String { dict[k] as? String ?? "" }
        vodId = str("vod_id")
        vodName = str("vod_name")
        typeName = str("type_name")
        vodPic = str("vod_pic")
        vodRemarks = str("vod_remarks")
        vodYear = str("vod_year")
        vodArea = str("vod_area")
        vodDirector = str("vod_director")
        vodActor = str("vod_actor")
        vodContent = str("vod_content")
        vodPlayFrom = str("vod_play_from")
        vodPlayUrl = str("vod_play_url")
        vodTag = str("vod_tag")
        action = str("action")
        var fs: [Flag] = []
        if let arr = dict["vod_flags"] as? [Any] {
            for f in arr { if let fd = f as? [String: Any], let flag = Flag.from(dict: fd) { fs.append(flag) } }
        }
        flags = fs
        buildFlags()
    }

    /// Build `flags` from the raw `$`-syntax `vod_play_from`/`vod_play_url` when no `vod_flags`.
    private mutating func buildFlags() {
        if !flags.isEmpty {
            for i in flags.indices { flags[i].buildEpisodes() }
            return
        }
        let names = vodPlayFrom.components(separatedBy: "$$$")
        let urls = vodPlayUrl.components(separatedBy: "$$$")
        var out: [Flag] = []
        for i in names.indices {
            let name = names[i].trimmingCharacters(in: .whitespaces)
            let url = i < urls.count ? urls[i] : ""
            if name.isEmpty || url.isEmpty { continue }
            var f = Flag(flag: name, show: name, url: url, episodes: [])
            f.buildEpisodes()
            out.append(f)
        }
        flags = out
    }

    var isFolder: Bool { vodTag == "folder" }
    var isAction: Bool { !action.isEmpty }
}

// MARK: - Result

/// Top-level spider result, mirroring Android `Result`.
struct Result {
    var types: [VodClass] = []
    var list: [Vod] = []
    var pagecount: Int = 0
    var playUrl: String = ""
    var url: String = ""
    var header: [String: String] = [:]
    var flag: String = ""
    var msg: String = ""

    static func parse(_ json: String) -> Result {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Result()
        }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> Result {
        var r = Result()
        if let arr = object["class"] as? [Any] {
            for e in arr { if let d = e as? [String: Any], let c = VodClass.from(dict: d) { r.types.append(c) } }
        }
        if let arr = object["list"] as? [Any] {
            for e in arr { if let d = e as? [String: Any] { r.list.append(Vod(dict: d)) } }
        }
        r.pagecount = (object["pagecount"] as? Int) ?? ((object["pagecount"] as? String).map { Int($0) ?? 0 } ?? 0)
        r.playUrl = (object["playUrl"] as? String) ?? ""
        r.url = (object["url"] as? String) ?? ""
        r.flag = (object["flag"] as? String) ?? ""
        r.msg = (object["msg"] as? String) ?? ""
        if let h = object["header"] as? [String: Any] {
            for (k, v) in h { r.header[k] = "\(v)" }
        }
        return r
    }
}

// MARK: - Live

/// A live group / channel, mirroring Android `Group`/`Channel`.
struct LiveGroup {
    var name: String
    var channels: [LiveChannel]
}

struct LiveChannel {
    var name: String
    var url: String
}

enum LiveParser {
    /// Parse a `Group`-style list from a live config JSON string.
    static func parseGroups(_ json: String) -> [LiveGroup] {
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        var groups: [LiveGroup] = []
        for e in arr {
            guard let d = e as? [String: Any] else { continue }
            let name = (d["name"] as? String) ?? ""
            var channels: [LiveChannel] = []
            if let ch = d["channel"] as? [Any] {
                for c in ch {
                    if let cd = c as? [String: Any] {
                        channels.append(LiveChannel(
                            name: (cd["name"] as? String) ?? "",
                            url: (cd["url"] as? String) ?? ""))
                    }
                }
            }
            if !name.isEmpty || !channels.isEmpty {
                groups.append(LiveGroup(name: name, channels: channels))
            }
        }
        return groups
    }
}


extension LiveParser {
    static func parseM3U(_ text: String) -> [LiveGroup] {
        var groups: [LiveGroup] = []
        var current: Int?
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix(","), t.contains("#genre#") {
                let name = t.replacingOccurrences(of: "#genre#", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                groups.append(LiveGroup(name: name, channels: []))
                current = groups.count - 1
            } else if let i = t.firstIndex(of: ","), let idx = current {
                let name = String(t[..<i]).trimmingCharacters(in: .whitespaces)
                let url = String(t[t.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !url.isEmpty { groups[idx].channels.append(LiveChannel(name: name, url: url)) }
            }
        }
        return groups
    }
}