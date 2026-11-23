import FaceRecognitionKit
import UIKit

/// Bottom tabs: Identity · People · Attribute · Liveness · Settings.
final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let identity = IdentifyViewController(mode: .identify)
        identity.tabBarItem = UITabBarItem(title: "Identity", image: UIImage(systemName: "faceid"), tag: 0)

        let people = PeopleViewController()
        people.tabBarItem = UITabBarItem(title: "People", image: UIImage(systemName: "person.2"), tag: 1)

        let attribute = IdentifyViewController(mode: .attribute)
        attribute.tabBarItem = UITabBarItem(title: "Attribute", image: UIImage(systemName: "face.dashed"), tag: 2)

        let liveness = LivenessViewController()
        liveness.tabBarItem = UITabBarItem(title: "Liveness", image: UIImage(systemName: "eye"), tag: 3)

        let settings = SettingsViewController()
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 4)

        viewControllers = [identity, people, attribute, liveness, settings].map {
            UINavigationController(rootViewController: $0)
        }
        selectedIndex = 0
    }
}

/// Logo splash. The engine is already activating on a background queue.
final class SplashViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let logo = UIImageView(image: UIImage(named: "FacePluginLogo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logo.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let window = self?.view.window else { return }
            window.rootViewController = MainTabBarController()
            UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: nil)
        }
    }
}
