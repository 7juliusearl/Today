import Foundation

@main struct WindowSpaceTests {
    static func main() {
        let screen = CGRect(x: 0, y: 40, width: 1440, height: 840)
        let right = CGRect(x: 1000, y: 40, width: 440, height: 840)
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: right) == CGRect(x: 0, y: 40, width: 992, height: 840))
        let top = CGRect(x: 0, y: 580, width: 1440, height: 300)
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: top) == CGRect(x: 0, y: 40, width: 1440, height: 532))
        let bottom = CGRect(x: 0, y: 40, width: 1440, height: 300)
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: bottom) == CGRect(x: 0, y: 348, width: 1440, height: 532))
        let left = CGRect(x: 0, y: 40, width: 440, height: 840)
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: left) == CGRect(x: 448, y: 40, width: 992, height: 840))
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: screen) == nil)
        assert(DashboardSpace.remainingFrame(screen: screen, dashboard: CGRect(x: 2000, y: 0, width: 400, height: 400)) == nil)
        assert(DashboardSpace.isFilled(screen, screen: screen))
        assert(DashboardSpace.isFilled(screen.insetBy(dx: 8, dy: 8), screen: screen))
        assert(!DashboardSpace.isFilled(CGRect(x: 0, y: 40, width: 720, height: 840), screen: screen))
        let secondScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let onSecond = CGRect(x: -480, y: -200, width: 480, height: 1080)
        let remaining = DashboardSpace.remainingFrame(screen: secondScreen, dashboard: onSecond)!
        assert(remaining == CGRect(x: -1920, y: -200, width: 1432, height: 1080))
        assert(!remaining.intersects(onSecond))
        assert(DashboardSpace.flip(DashboardSpace.flip(secondScreen, primaryTop: 900), primaryTop: 900) == secondScreen)
        assert(DashboardSpace.flip(CGRect(x: 0, y: 600, width: 400, height: 300), primaryTop: 900).minY == 0)
        print("Window space tests passed")
    }
}
