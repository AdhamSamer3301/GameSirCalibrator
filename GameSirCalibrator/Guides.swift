/// Each controller's built-in calibration routine. The calibration runs inside the controller;
/// the app only shows these steps. To add your model, append an entry (see README).
struct Guide: Identifiable, Hashable {
    let model: String
    let steps: [String]
    var id: String { model }
}

let guides = [
    Guide(model: "GameSir Cyclone 2", steps: [
        "Hold View + Menu + Home until the Home light slowly flashes white.",
        "Don't touch the sticks or triggers. Press A. The Home light turns off.",
        "Press LT and RT all the way down, then rotate both sticks around their edge 3 times each.",
        "Press A. The Home light comes back on: the calibration is saved, even after a restart.",
    ]),
    Guide(model: "Other controller", steps: [
        "Find your controller's calibration button combo in its manual (gamesir.com/support).",
        "Follow the manual's steps on the controller. Most ask you to leave the sticks centred, then rotate them fully.",
        "When the controller shows it's done, continue here to measure again.",
    ]),
]
