// 공부 감시하는 엄마 — 공부 시간 동안 유튜브·인스타 같은 딴짓 탭을 열면 엄마가 달려와서 닫는다.
// 같은 사이트 경고 2번이면 공부 끝날 때까지 그 사이트 금지(열자마자 닫힘).
// 도트 엄마 + 공부 완료 시 간식 랜덤 보상(딸·아들 6종씩). 모든 창의 모든 탭을 봄. assets 폴더를 실행 파일 옆에 둡니다.
// macOS 12+: ./run.command   안전한 화면 미리보기: ./preview.command   검사: ./mom --selftest
import AppKit
import SwiftUI
import ImageIO

// 딴짓 사이트 → 엄마가 부르는 이름 (하위 도메인 포함, 금지는 이름 단위라 youtu.be도 같이 막힘)
let distractions = [
    "youtube.com": "유튜브", "youtu.be": "유튜브", "instagram.com": "인스타", "tiktok.com": "틱톡",
    "netflix.com": "넷플릭스", "tving.com": "티빙", "wavve.com": "웨이브", "coupangplay.com": "쿠팡플레이", "laftel.net": "라프텔",
    "twitch.tv": "트위치", "chzzk.naver.com": "치지직", "sooplive.co.kr": "숲", "afreecatv.com": "아프리카",
    "x.com": "트위터", "twitter.com": "트위터", "facebook.com": "페북", "reddit.com": "레딧",
    "comic.naver.com": "웹툰", "webtoons.com": "웹툰", "page.kakao.com": "카카오페이지",
    // 쇼핑
    "coupang.com": "쿠팡", "musinsa.com": "무신사", "zigzag.kr": "지그재그", "a-bly.com": "에이블리", "29cm.co.kr": "29CM",
    "11st.co.kr": "11번가", "gmarket.co.kr": "G마켓", "oliveyoung.co.kr": "올리브영", "shopping.naver.com": "네이버쇼핑",
    "aliexpress.com": "알리", "temu.com": "테무",
    // 커뮤니티·위키
    "namu.wiki": "나무위키", "dcinside.com": "디시", "fmkorea.com": "에펨코리아", "theqoo.net": "더쿠",
    "instiz.net": "인스티즈", "ruliweb.com": "루리웹",
    // 디스코드 웹 (앱은 감시 안 함)
    "discord.com": "디스코드", "discord.gg": "디스코드",
    // 게임
    "steampowered.com": "스팀", "steamcommunity.com": "스팀", "nexon.com": "넥슨", "netmarble.net": "넷마블",
    "hangame.com": "한게임", "op.gg": "OP.GG", "leagueoflegends.com": "롤", "poki.com": "포키",
]

func site(_ url: String) -> String? {
    guard let host = URL(string: url)?.host?.lowercased() else { return nil }
    return distractions.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value
}

// 받침 있으면 a, 없으면 b — "유튜브는", "쿠팡은" (한글로 안 끝나면 b)
func josa(_ word: String, _ a: String, _ b: String) -> String {
    guard let last = word.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(last) else { return word + b }
    return word + ((last - 0xAC00) % 28 == 0 ? b : a)
}

// 지원 브라우저. 크롬 계열과 사파리 모두 "tab 번호 of window 번호" 로 탭을 가리킴
let browsers: Set = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
                     "com.naver.Whale", "com.vivaldi.Vivaldi", "com.apple.Safari"]

var denied = Set<String>()

// ponytail: NSAppleScript는 메인 스레드라 읽을 때마다 잠깐 멈춤 — 엄마가 가만히 있을 때만 부르니 괜찮음
@discardableResult
func osa(_ id: String, _ cmd: String) -> NSAppleEventDescriptor? {
    var err: NSDictionary?
    let out = NSAppleScript(source: "tell application id \"\(id)\" to \(cmd)")?.executeAndReturnError(&err)
    if err?[NSAppleScript.errorNumber] as? Int == -1743, denied.insert(id).inserted {
        print("⚠️ \(id) 제어 권한이 없어서 엄마가 못 봐요 → 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 켜주세요")
    }
    return err == nil ? out : nil
}

// 걸린 탭. window·tab 은 AppleScript 번호(1부터, 창은 앞에 있는 순서)
struct Caught {
    let id: String, pid: pid_t, name: String, window: Int, tab: Int
    var url: String? { osa(id, "get URL of tab \(tab) of window \(window)")?.stringValue }
    func close() { osa(id, "close tab \(tab) of window \(window)") }
}

// 켜져 있는 브라우저의 모든 창·모든 탭 주소를 한 번에 읽는다 (뒤에 숨겨둔 탭도 걸림)
func caught() -> Caught? {
    for app in NSWorkspace.shared.runningApplications {
        guard let id = app.bundleIdentifier, browsers.contains(id),
              let windows = osa(id, "get URL of every tab of every window") else { continue }
        for w in 0..<windows.numberOfItems {
            guard let tabs = windows.atIndex(w + 1) else { continue }
            for t in 0..<tabs.numberOfItems {
                if let url = tabs.atIndex(t + 1)?.stringValue, let name = site(url) {
                    return Caught(id: id, pid: app.processIdentifier, name: name, window: w + 1, tab: t + 1)
                }
            }
        }
    }
    return nil
}

// 그 브라우저 n번째 창의 위치, 없으면 맨 앞 창 (주 화면 좌상단 기준이라 SwiftUI 좌표와 같음)
// ponytail: 최소화된 창이 있으면 AppleScript 창 순서와 화면 창 순서가 어긋날 수 있음 — 그땐 다른 창으로 달려감
func browserWindow(_ pid: pid_t, _ n: Int) -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let frames = list
        .filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 }
        .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } }
        .filter { $0.width > 200 }
    return n <= frames.count ? frames[n - 1] : frames.first
}

// 시트의 실제 포즈 경계를 사용합니다. 이미지는 원본 그대로 두고 메모리에서만 자릅니다.
// 시작 화면에서 고름. 엄마가 부르는 호칭과 끝나고 받는 간식이 달라집니다.
enum Child: String, CaseIterable {
    case daughter = "딸", son = "아들"
    var gender: String { self == .daughter ? "여자" : "남자" }   // 시작 화면에 보이는 답
}

struct Snack: Identifiable {
    let id: String
    let name: String
    let line: String
    let file: String   // assets/snacks/<file>.png 단독 그림, assets/holding/mom-<file>.png 엄마가 든 전신 그림
    let child: Child

    static let all: [Snack] = [
        Snack(id: "apple", name: "사과", line: "사과 깎아놨다.\n색 변하기 전에 얼른 먹어.", file: "01-apple", child: .son),
        Snack(id: "tangerine", name: "귤", line: "귤 까놨어.\n손 노래지게 먹지 말고 적당히~", file: "02-tangerine", child: .daughter),
        Snack(id: "strawberry", name: "딸기", line: "딸기 씻어놨다.\n완전 달아, 먹어봐.", file: "03-strawberry", child: .daughter),
        Snack(id: "cookie", name: "쿠키", line: "쿠키 구워놨어.\n우유랑 같이 먹어.", file: "04-cookie", child: .son),
        Snack(id: "sandwich", name: "샌드위치", line: "출출하지?\n샌드위치 싸놨으니까 먹어.", file: "05-sandwich", child: .son),
        Snack(id: "gimbap", name: "김밥", line: "김밥 말아놨다.\n꽁다리는 엄마가 먹었어~", file: "06-gimbap", child: .son),
        Snack(id: "tteok", name: "떡", line: "쫀득한 떡 사 왔어.\n목 막히니까 꼭꼭 씹어 먹어.", file: "07-rice-cake", child: .son),
        Snack(id: "bungeoppang", name: "붕어빵", line: "붕어빵 사 왔다.\n식기 전에 얼른 먹어.", file: "08-bungeoppang", child: .son),
        Snack(id: "dujjonku", name: "두쫀쿠", line: "두쫀쿠 그거 줄 서서 사 왔다.\n엄마도 한 입만 줘.", file: "09-dubai-chewy-cookie", child: .daughter),
        Snack(id: "mala", name: "마라샹궈", line: "마라샹궈 시켜놨어.\n맵게 해달랬다, 먹어.", file: "10-mala-xiangguo", child: .daughter),
        Snack(id: "buttertteok", name: "버터떡", line: "버터떡 데워놨어.\n겉바속쫀일 때 먹어.", file: "11-butter-mochi", child: .daughter),
        Snack(id: "matcha", name: "말차 아이스크림", line: "말차 아이스크림 사 왔다.\n녹기 전에 먹어.", file: "12-matcha-ice-cream", child: .daughter),
    ]
}

enum AssetError: LocalizedError {
    case unreadable(String)
    case invalidGrid(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path): return "이미지를 읽을 수 없어요: \(path)"
        case .invalidGrid(let path): return "캐릭터 시트의 크기와 포즈 경계를 확인해주세요: \(path)"
        }
    }
}

final class Artwork {
    // (x, y, width, height), 1448 × 1086 원본 기준. 균등 분할하면 달리는 발이 잘립니다.
    static let actionBounds: [CGRect] = [
        CGRect(x: 49, y: 7, width: 280, height: 548),
        CGRect(x: 418, y: 10, width: 300, height: 545),
        CGRect(x: 774, y: 12, width: 287, height: 543),
        CGRect(x: 1140, y: 12, width: 292, height: 543),
        CGRect(x: 33, y: 575, width: 379, height: 490),
        CGRect(x: 415, y: 575, width: 287, height: 492),
        CGRect(x: 753, y: 576, width: 380, height: 491),
        CGRect(x: 1147, y: 576, width: 267, height: 490),
    ]
    let actions: [NSImage]
    let holding: [String: NSImage] // 간식 id → 엄마가 그 간식을 든 전신 그림
    let foods: [String: NSImage]   // 간식 id → 단독 그림
    let menuIcon: NSImage?

    init(directory: URL) throws {
        actions = try Self.readAtlas(directory.appendingPathComponent("mom-actions.png"), bounds: Self.actionBounds)
        // 그림마다 해상도가 달라서, 엄마 키를 동작 시트의 엄마 키(약 530px)에 맞춰 둡니다.
        holding = Dictionary(uniqueKeysWithValues: try Snack.all.map {
            ($0.id, try Self.trimmed(directory.appendingPathComponent("holding/mom-\($0.file).png"), height: 530))
        })
        foods = Dictionary(uniqueKeysWithValues: try Snack.all.map {
            ($0.id, try Self.trimmed(directory.appendingPathComponent("snacks/\($0.file).png")))
        })
        let icon = NSImage(contentsOf: directory.appendingPathComponent("icons/MenuBarTemplate@2x.png"))
        icon?.size = NSSize(width: 18, height: 18)   // 36px 그림을 18pt 로 — 레티나에서 1:1
        icon?.isTemplate = true                      // 메뉴 막대 밝기·다크 모드에 맞춰 시스템이 칠함
        menuIcon = icon
    }

    // 그림마다 캔버스 크기와 여백이 달라서, 투명한 테두리를 잘라내 그림만 남깁니다. height 를 주면 그 높이로 맞춤.
    private static func trimmed(_ url: URL, height: CGFloat? = nil) throws -> NSImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AssetError.unreadable(url.path)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)   // 위쪽 줄부터 저장됨
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let food = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else {
            throw AssetError.unreadable(url.path)
        }
        let h = height ?? CGFloat(food.height)
        return NSImage(cgImage: food, size: NSSize(width: CGFloat(food.width) * h / CGFloat(food.height), height: h))
    }

    private static func readAtlas(_ url: URL, bounds: [CGRect]) throws -> [NSImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AssetError.unreadable(url.path)
        }
        guard sheet.width == 1448, sheet.height == 1086 else {
            throw AssetError.invalidGrid(url.path)
        }
        var result: [NSImage] = []
        let sheetRect = CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)
        for rect in bounds {
            guard sheetRect.contains(rect), let frame = sheet.cropping(to: rect) else {
                throw AssetError.invalidGrid(url.path)
            }
            result.append(NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height)))
        }
        return result
    }
}

enum Pose {
    case watch, hello, scold, pleased, runLeft, runRight, reward
    var moving: Bool { self == .runLeft || self == .runRight }
}

enum Palette {
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.23, green: 0.18, blue: 0.24)
    static let muted = Color(red: 0.49, green: 0.43, blue: 0.49)
    static let purple = Color(red: 0.44, green: 0.33, blue: 0.57)
    static let lavender = Color(red: 0.92, green: 0.88, blue: 0.96)
    static let warning = Color(red: 0.68, green: 0.29, blue: 0.23)
}

final class Mom: ObservableObject {
    @Published var pos = CGPoint.zero
    @Published var pose: Pose = .hello
    @Published var line: String?
    @Published var caption = "엄마의 한마디"
    @Published var urgent = false
    @Published var snack = Snack.all[0]
}

struct CharacterView: View {
    let artwork: Artwork
    let pose: Pose
    var snack = Snack.all[0]

    private func frame(at date: Date) -> NSImage {
        switch pose {
        case .watch: return artwork.actions[0]
        case .hello: return artwork.actions[1]
        case .scold: return artwork.actions[2]
        case .pleased: return artwork.actions[3]
        case .runLeft, .runRight:
            return artwork.actions[4 + Int(date.timeIntervalSinceReferenceDate * 8) % 4]
        case .reward: return artwork.holding[snack.id]!
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: !pose.moving)) { timeline in
            GeometryReader { geometry in
                let image = frame(at: timeline.date)
                // 공통 배율과 발 기준선을 유지해 프레임이 바뀔 때 크기가 튀지 않게 합니다.
                let scale = min(geometry.size.width / 400, geometry.size.height / 560)
                Image(nsImage: image)
                    .resizable().interpolation(.none)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .scaleEffect(x: pose == .runRight ? -1 : 1, y: 1)
                    .position(x: geometry.size.width / 2,
                              y: geometry.size.height - image.size.height * scale / 2)
            }
        }
        .accessibilityLabel(pose == .reward ? "엄마가 간식을 들고 있어요" : "공부를 지켜보는 엄마")
    }
}

struct MomView: View {
    @ObservedObject var mom: Mom
    let size: CGSize
    let artwork: Artwork

    var body: some View {
        ZStack {
            CharacterView(artwork: artwork, pose: mom.pose, snack: mom.snack)
                .frame(width: 164, height: 190)
                // 구석에서 지켜볼 땐 흐릿하게(공부 방해 안 되게), 달려오거나 혼낼 땐 또렷하게
                .opacity(mom.pose == .watch ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.4), value: mom.pose == .watch)
                .position(mom.pos)
            if let line = mom.line {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: mom.urgent ? "exclamationmark.circle.fill" : "heart.fill")
                        Text(mom.caption)
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(mom.urgent ? Palette.warning : Palette.purple)
                    Text(line)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 17).padding(.vertical, 13)
                .frame(width: 272, alignment: .leading)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.purple.opacity(0.18), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.13), radius: 10, x: 0, y: 4)
                .position(x: min(max(mom.pos.x, 148), size.width - 148),
                          y: min(max(mom.pos.y - 146, 62), size.height - 62))
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct SetupView: View {
    let artwork: Artwork
    let onStart: (Int, Child) -> Void
    let onCancel: () -> Void
    @State private var minutes = 60
    @State private var child = Child.daughter
    private let durations = [("1분 · 테스트", 1), ("25분", 25), ("30분", 30), ("1시간", 60),
                             ("1시간 30분", 90), ("2시간", 120), ("3시간", 180),
                             ("4시간", 240), ("5시간", 300), ("6시간", 360)]

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("엄마 안 잔다").font(.system(size: 22, weight: .heavy, design: .rounded))
                Spacer()
                Label("집중 시간", systemImage: "eye.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.purple)
            }
            HStack(spacing: 20) {
                CharacterView(artwork: artwork, pose: .hello)
                    .frame(width: 128, height: 170)
                VStack(alignment: .leading, spacing: 12) {
                    Text("공부는 네가,\n옆에서 지키는 건 엄마가.")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("딴짓하면 바로 달려간다.\n다 하면 간식 줄게.")
                        .font(.system(size: 13)).foregroundColor(Palette.muted).lineSpacing(4)
                }
            }
            VStack(spacing: 12) {
                HStack {
                    Label("당신의 성별은?", systemImage: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("당신의 성별은?", selection: $child) {
                        ForEach(Child.allCases, id: \.self) { Text($0.gender).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                HStack {
                    Label("오늘 얼마나 공부할까?", systemImage: "clock")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("공부 시간", selection: $minutes) {
                        ForEach(durations, id: \.1) { duration in
                            Text(duration.0).tag(duration.1)
                        }
                    }
                    .labelsHidden().frame(width: 150)
                }
            }
            .padding(14).background(Palette.lavender.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            Label("딴짓 탭은 닫아요. 같은 사이트에 두 번 걸리면 공부 끝날 때까지 금지!", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("끝나면 엄마가 간식 줄게").font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("\(child.rawValue)이 좋아하는 간식 중 랜덤").font(.system(size: 10)).foregroundColor(Palette.muted)
                }
                HStack(spacing: 0) {
                    ForEach(Snack.all.filter { $0.child == child }) { snack in
                        VStack(spacing: 4) {
                            Image(nsImage: artwork.foods[snack.id]!)
                                .resizable().interpolation(.none).scaledToFit().frame(height: 33)
                            Text(snack.name).font(.system(size: 9, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Button("오늘은 쉴래", action: onCancel).buttonStyle(.plain)
                    .foregroundColor(Palette.muted).keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: { onStart(minutes, child) }) {
                    HStack(spacing: 8) {
                        Text("공부 시작").fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(Palette.purple, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 540)
        .foregroundColor(Palette.ink).background(Palette.paper)
    }
}

@MainActor
final class StudyController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let artwork: Artwork
    private let demo: Bool
    private let mom = Mom()
    private var setupWindow: NSWindow?
    private var panel: NSPanel?
    private var status: NSStatusItem?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var screen = CGRect.zero
    private var home = CGPoint.zero
    private var end = Date.distantFuture
    private var strikes: [String: Int] = [:]
    private var banned = Set<String>()
    private var busy = true
    private var sessionStarted = false
    private var finished = false
    private var child = Child.daughter

    init(artwork: Artwork, demo: Bool) {
        self.artwork = artwork
        self.demo = demo
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let primary = NSScreen.screens.first else {
            NSApp.terminate(nil)
            return
        }
        screen = primary.frame
        // 오른쪽 아래에서 얼굴과 어깨만 빼꼼. 좌표는 주 화면의 왼쪽 위 기준입니다.
        home = CGPoint(x: screen.width - 92, y: screen.height - 35)
        mom.pos = CGPoint(x: screen.width / 2, y: screen.height / 2)
        makeOverlay()
        makeMenu()
        if demo { startDemo() } else { showSetup() }
    }

    private func makeOverlay() {
        let window = NSPanel(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: MomView(mom: mom, size: screen.size, artwork: artwork))
        panel = window
    }

    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = artwork.menuIcon ?? NSImage(systemSymbolName: "eye", accessibilityDescription: "엄마 안 잔다")
        item.button?.imagePosition = .imageLeading
        item.button?.title = demo ? " 미리보기" : " 준비 중"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu()
        let heading = NSMenuItem(title: "엄마 안 잔다 · 도트 엄마", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "엄마 몰래 그만두기", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        status = item
    }

    private func showSetup() {
        let view = SetupView(artwork: artwork, onStart: { [weak self] minutes, child in
            self?.start(minutes: minutes, child: child)
        }, onCancel: { NSApp.terminate(nil) })
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "엄마 안 잔다"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !sessionStarted { NSApp.terminate(nil) }
    }

    private func start(minutes: Int, child: Child) {
        sessionStarted = true
        self.child = child
        setupWindow?.close()
        setupWindow = nil
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                          reason: "엄마가 공부 시간을 지켜보는 중")
        end = Date().addingTimeInterval(Double(minutes * 60))
        panel?.orderFrontRegardless()
        mom.pose = .hello
        say("우리 \(child.rawValue) 공부해~\n엄마 없는 셈 쳐.", caption: "공부 시작")
        after(2.8) { [weak self] in self?.returnHome() }
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        tick()
    }

    private func say(_ text: String, caption: String = "엄마의 한마디", urgent: Bool = false) {
        mom.caption = caption
        mom.urgent = urgent
        withAnimation(.easeOut(duration: 0.15)) { mom.line = text }
    }

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    private func run(to target: CGPoint, then completion: @escaping () -> Void) {
        let distance = hypot(target.x - mom.pos.x, target.y - mom.pos.y)
        let duration = max(0.35, min(3.5, distance / 720))
        mom.pose = target.x >= mom.pos.x ? .runRight : .runLeft
        withAnimation(.linear(duration: duration)) { mom.pos = target }
        after(duration, completion)
    }

    private func returnHome() {
        mom.line = nil
        run(to: home) { [weak self] in
            self?.mom.pose = .watch
            self?.busy = false
        }
    }

    @objc private func tick() {
        guard !finished else { return }
        let remaining = max(0, Int(ceil(end.timeIntervalSinceNow)))
        status?.button?.title = String(format: " %d:%02d:%02d", remaining / 3600, remaining / 60 % 60, remaining % 60)
        guard !busy else { return }
        if remaining == 0 {
            finish()
            return
        }
        guard let caughtSite = caught() else { return }
        busy = true
        if banned.contains(caughtSite.name) {
            // 읽은 뒤 탭이 바뀌었으면 다른 사이트의 탭을 닫지 않습니다.
            if caughtSite.url.flatMap(site) == caughtSite.name {
                caughtSite.close()
                mom.pose = .scold
                say("\(josa(caughtSite.name, "은", "는")) 막았다고 했지!\n공부나 해.", caption: "지금은 공부 시간", urgent: true)
            }
            after(2.5) { [weak self] in
                self?.mom.pose = .watch
                self?.mom.line = nil
                self?.busy = false
            }
            return
        }
        let count = strikes[caughtSite.name, default: 0]
        say(count == 0 ? "너 지금 \(caughtSite.name) 보니?\n공부한다며!" : "또 \(josa(caughtSite.name, "이야", "야"))?!\n엄마 진짜 간다!",
            caption: "딴짓 발견", urgent: true)
        let bounds = browserWindow(caughtSite.pid, caughtSite.window) ?? CGRect(x: screen.width / 2, y: screen.height / 2, width: 0, height: 0)
        let destination = CGPoint(x: min(max(bounds.midX, 155), screen.width - 155),
                                  y: min(max(bounds.minY + 180, 235), screen.height - 105))
        run(to: destination) { [weak self] in
            guard let self = self else { return }
            guard caughtSite.url.flatMap(site) == caughtSite.name else {
                self.returnHome()
                return
            }
            caughtSite.close()
            self.strikes[caughtSite.name, default: 0] += 1
            let strikes = self.strikes[caughtSite.name, default: 0]
            self.mom.pose = .scold
            if strikes >= 2 {
                self.banned.insert(caughtSite.name)
                self.say("말을 안 듣네?\n\(josa(caughtSite.name, "은", "는")) 공부 끝날 때까지 금지!", caption: "경고 2/2 · 공부 끝날 때까지 금지", urgent: true)
            } else {
                self.say("한 번만 더 걸려봐.\n\(caughtSite.name) 아예 막아버린다?", caption: "경고 1/2", urgent: true)
            }
            self.after(3.2) { [weak self] in self?.returnHome() }
        }
    }

    private func finish() {
        finished = true
        busy = true
        timer?.invalidate()
        timer = nil
        status?.button?.title = " 공부 끝!"
        mom.line = nil
        // 그림과 이름·대사를 하나의 Snack에서 함께 선택해 항상 일치하게 합니다.
        let snack = Snack.all.filter { $0.child == child }.randomElement()!
        run(to: CGPoint(x: screen.width / 2, y: screen.height / 2)) { [weak self] in
            guard let self = self else { return }
            self.show(snack: snack)
            self.after(6) { [weak self] in self?.leave() }
        }
    }

    // 간식 주고 인사한 뒤 화면 밖으로 달려 나가면 앱이 꺼집니다(run.command 도 같이 끝남).
    private func leave() {
        say("고생했다 우리 \(child.rawValue)~\n엄마는 드라마 보러 간다.", caption: "공부 끝")
        after(2.5) { [weak self] in
            guard let self = self else { return }
            self.mom.line = nil
            self.run(to: CGPoint(x: self.screen.width + 200, y: self.mom.pos.y)) { NSApp.terminate(nil) }
        }
    }

    private func show(snack: Snack) {
        mom.snack = snack
        mom.pose = .reward
        say(snack.line, caption: "오늘의 간식 · \(snack.name)")
    }

    // 브라우저를 읽거나 닫지 않는 데모. 감시 → 달리기 → 잔소리 → 간식 12종 → 퇴장·종료.
    private func startDemo() {
        sessionStarted = true
        panel?.orderFrontRegardless()
        mom.pos = CGPoint(x: screen.width * 0.67, y: screen.height / 2)
        mom.pose = .watch
        say("브라우저는 건드리지 않는\n화면 미리보기야.", caption: "엄마 안 잔다 · 미리보기")
        after(2) { [weak self] in
            guard let self = self else { return }
            self.mom.line = nil
            self.run(to: CGPoint(x: self.screen.width * 0.33, y: self.screen.height / 2)) { [weak self] in
                guard let self = self else { return }
                self.mom.pose = .scold
                self.say("엄마 다 보고 있어!", caption: "잔소리 표정", urgent: true)
                self.after(2) { [weak self] in
                    guard let self = self else { return }
                    self.mom.line = nil
                    self.run(to: CGPoint(x: self.screen.width / 2, y: self.screen.height / 2)) { [weak self] in
                        self?.previewSnack(at: 0)
                    }
                }
            }
        }
    }

    private func previewSnack(at index: Int) {
        guard index < Snack.all.count else {
            leave()
            return
        }
        show(snack: Snack.all[index])
        after(2.5) { [weak self] in self?.previewSnack(at: index + 1) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let activity = activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}

// 실행 파일 기준으로 찾으므로 Finder에서 열거나 다른 폴더에서 실행해도 됩니다.
let arguments = Array(CommandLine.arguments.dropFirst())
// 앱(.app)이면 Contents/Resources/assets, 그냥 실행 파일이면 그 옆의 assets
var assetsDirectory = Bundle.main.resourceURL!.appendingPathComponent("assets", isDirectory: true)
if let index = arguments.firstIndex(of: "--assets") {
    guard index + 1 < arguments.count else {
        fputs("사용법: ./mom [--assets 폴더] [--demo | --selftest]\n", stderr)
        exit(1)
    }
    assetsDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
}

do {
    let artwork = try Artwork(directory: assetsDirectory)
    if arguments.contains("--selftest") {
        precondition(site("https://www.youtube.com/watch?v=x") == "유튜브")
        precondition(site("https://youtu.be/x") == "유튜브")
        precondition(site("https://m.instagram.com/p/1") == "인스타")
        precondition(site("https://chzzk.naver.com/live/1") == "치지직")
        precondition(site("https://www.naver.com/") == nil)
        precondition(site("https://notyoutube.com/") == nil)
        precondition(site("https://youtube.com.evil.example/") == nil)
        precondition(site("https://www.google.com/search?q=youtube.com") == nil)
        precondition(site("https://www.coupang.com/vp/1") == "쿠팡" && site("https://www.coupangplay.com/") == "쿠팡플레이")
        precondition(site("https://maplestory.nexon.com/") == "넥슨" && site("https://store.steampowered.com/") == "스팀")
        precondition(site("https://namu.wiki/w/x") == "나무위키" && site("https://www.naver.com/") == nil)
        precondition(josa("유튜브", "은", "는") == "유튜브는" && josa("쿠팡", "은", "는") == "쿠팡은" && josa("OP.GG", "은", "는") == "OP.GG는")
        precondition(Snack.all.count == 12 && Set(Snack.all.map(\.id)).count == 12)
        precondition(Child.allCases.allSatisfy { child in Snack.all.filter { $0.child == child }.count == 6 })
        precondition(artwork.actions.count == 8 && artwork.holding.count == 12 && artwork.foods.count == 12)
        for image in artwork.actions + Array(artwork.holding.values) + Array(artwork.foods.values) {
            precondition(image.size.width > 0 && image.size.height > 0)
        }
        print("ok · 사이트 구분 / 도트 동작 8개 / 간식 12종(딸 6 · 아들 6) / 메뉴 아이콘 \(artwork.menuIcon == nil ? "없음" : "있음")")
        exit(0)
    }
    MainActor.assumeIsolated {   // 최상위 코드는 메인 스레드에서 돌지만 컴파일러는 모르므로 알려줌
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = StudyController(artwork: artwork, demo: arguments.contains("--demo"))
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
} catch {
    fputs("\(error.localizedDescription)\n압축을 모두 푼 뒤 run.command를 실행해주세요.\n", stderr)
    exit(1)
}

