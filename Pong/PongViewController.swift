/// Импортируем библиотеку UI-компонентов (элементы интерфейса)
import UIKit
import AVFoundation

/// Это класс единственного экрана нашего приложения
///
/// В классе есть элементы отображения игры:
/// - `ballView` - мяч
/// - `userPaddleView` - платформа игрока
/// - `enemyPaddleView` - платформа сопернка
///
/// Также в классе данного экрана настраивается физика взаимодействия элементов
/// в функции `enableDynamics()`
///
/// А еще в этом классе реализована обработка движения пальца по экрану,
/// с помощью обработки этого жеста игрок может двигать свою платформу и отталкивать мяч
///
class PongViewController: UIViewController {

    // MARK: - Nested Types

    private enum DefaultsKey {
        static let bestScore = "bestUserScore"
        static let cpuDifficulty = "cpuDifficulty"
    }

    private enum GameStyle {
        static let fieldBackgroundTopColor = UIColor(red: 0.05, green: 0.11, blue: 0.21, alpha: 1.0)
        static let fieldBackgroundBottomColor = UIColor(red: 0.01, green: 0.25, blue: 0.34, alpha: 1.0)
        static let playerPaddleColor = UIColor(red: 0.97, green: 0.84, blue: 0.33, alpha: 1.0)
        static let enemyPaddleColor = UIColor(red: 0.99, green: 0.43, blue: 0.33, alpha: 1.0)
        static let ballColor = UIColor(red: 0.74, green: 0.98, blue: 0.98, alpha: 1.0)
        static let lineColor = UIColor(red: 0.50, green: 0.87, blue: 0.91, alpha: 0.4)
        static let scoreColor = UIColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 1.0)
    }

    enum CPUDifficulty: String, CaseIterable {
        case easy
        case regular
        case hard
        case beast

        var title: String {
            switch self {
            case .easy:
                return "Easy"
            case .regular:
                return "Regular"
            case .hard:
                return "Hard"
            case .beast:
                return "Beast"
            }
        }

        var speedMultiplier: CGFloat {
            switch self {
            case .easy:
                return 0.75
            case .regular:
                return 1.0
            case .hard:
                return 1.2
            case .beast:
                return 1.45
            }
        }

        var progressionMultiplier: CGFloat {
            switch self {
            case .easy:
                return 0.8
            case .regular:
                return 1.0
            case .hard:
                return 1.1
            case .beast:
                return 1.25
            }
        }

        var speedCapMultiplier: CGFloat {
            switch self {
            case .easy:
                return 0.95
            case .regular:
                return 1.0
            case .hard:
                return 1.2
            case .beast:
                return 1.45
            }
        }

        var slowdownInterval: UInt8 {
            switch self {
            case .easy:
                return 3
            case .regular:
                return 8
            case .hard:
                return 14
            case .beast:
                return 0
            }
        }

        var slowdownFactor: CGFloat {
            switch self {
            case .easy:
                return 0.15
            case .regular:
                return 0.2
            case .hard:
                return 0.45
            case .beast:
                return 1.0
            }
        }
    }

    // MARK: - Overriden Properties

    /// Эта переопределенная переменная определяет допустимые ориентации экрана
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Subviews

    /// Это переменная отображения мяча
    @IBOutlet var ballView: UIView!

    /// Это переменная отображения платформы игрока
    @IBOutlet var userPaddleView: UIView!

    /// Это переменная отображения платформы соперника
    @IBOutlet var enemyPaddleView: UIView!

    /// Это переменная отображения разделяющей линии
    @IBOutlet var lineView: UIView!

    /// Это переменная отображения лэйбла со счетом игрока
    @IBOutlet var userScoreLabel: UILabel!

    // MARK: - Instance Properties

    /// Это переменная обработчика жеста движения пальцем по экрану
    var panGestureRecognizer: UIPanGestureRecognizer?

    /// Это переменная в которой мы будем запоминать последнее положение платформы пользователя,
    /// перед тем как пользователь начал двигать пальцем по экрану
    var lastUserPaddleOriginLocation: CGFloat = 0

    /// Это переменная таймера, который будет обновлять положение платформы соперника
    var enemyPaddleUpdateTimer: Timer?

    /// Это флаг `Bool`, имеет два возможных значения:
    /// - `true` - можно трактовать как "да"
    /// - `false` - можно трактовать как "нет"
    ///
    /// Он отвечает за необходимость запустить мяч по следующему нажатию на экран
    ///
    var shouldLaunchBallOnNextTap: Bool = false

    /// Это флаг `Bool`, который указывает "был ли запущен мяч"
    var hasLaunchedBall: Bool = false

    var enemyPaddleUpdatesCounter: UInt8 = 0

    var enemyScore: Int = 0 {
        didSet {
            updateUserScoreLabel()
        }
    }

    var bestUserScore: Int = UserDefaults.standard.integer(forKey: DefaultsKey.bestScore) {
        didSet {
            UserDefaults.standard.set(bestUserScore, forKey: DefaultsKey.bestScore)
        }
    }

    var isMatchOver: Bool = false
    var cpuDifficulty: CPUDifficulty = .regular {
        didSet {
            UserDefaults.standard.set(cpuDifficulty.rawValue, forKey: DefaultsKey.cpuDifficulty)
            updateUserScoreLabel()
        }
    }

    private let backgroundGradientLayer = CAGradientLayer()
    private var hasPresentedDifficultyPicker = false

    // NOTE: Все переменные ниже вплоть до 74-ой строки необходимы для настроек физики
    // Мы не будем вдаваться в подробности того, что это такое и как устроено
    var dynamicAnimator: UIDynamicAnimator?
    var ballPushBehavior: UIPushBehavior?
    var ballDynamicBehavior: UIDynamicItemBehavior?
    var userPaddleDynamicBehavior: UIDynamicItemBehavior?
    var enemyPaddleDynamicBehavior: UIDynamicItemBehavior?
    var collisionBehavior: UICollisionBehavior?

    // NOTE: Все переменный вплоть до 82-ой строки используются для реагирования
    // на стлокновения мяча - проигрывание звука столкновения и вибро-отклик
    var audioPlayers: [AVAudioPlayer] = []
    var audioPlayersLock = NSRecursiveLock()
    var softImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    var lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    var rigidImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// Эта переменная плеера предназначена для повторяющегося проигрывания фоновой музыки в игре
    var backgroundSoundAudioPlayer: AVAudioPlayer? = {
        guard
            let backgroundSoundURL = Bundle.main.url(forResource: "background", withExtension: "wav"),
            let audioPlayer = try? AVAudioPlayer(contentsOf: backgroundSoundURL)
        else { return nil }

        audioPlayer.volume = 0.5
        audioPlayer.numberOfLoops = -1

        return audioPlayer
    }()

    /// Эта переменная хранит счет пользователя
    var userScore: Int = 0 {
        didSet {
            /// При каждом обновлении значения переменной - обновляем текст в лэйбле
            if userScore > bestUserScore {
                bestUserScore = userScore
            }

            updateUserScoreLabel()
        }
    }

    // MARK: - Instance Methods

    /// Эта функция запускается 1 раз когда представление экрана загрузилось
    /// и вот-вот покажется в окне отображения
    override func viewDidLoad() {
        super.viewDidLoad()

        /*
        NOTE: 👨‍💻 Заметка по настройке экрана игры 👨‍💻

        Сейчас этот код выделен серым, потому что слэш со звездочкой
        над этим текстом и под этим текстом `/* */` делают его многострочным комменатрием.
        Также комментарии бывают однострочные, они начинаются с двух слэшей: `//`
        Комментарии в коде - это заметки разработчиков о работе кусочка кода.
        Комментарии не учитываются при работе программы, а просто игнорируются.

        Код на 127-ой строке настраивает все необходимое для игры.
        */

        configurePongGame()
    }

    /// Эта функция вызывается, когда экран PongViewController повяился на экране телефона
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // NOTE: Включаем динамику взаимодействия
        self.enableDynamics()

        if !hasPresentedDifficultyPicker {
            hasPresentedDifficultyPicker = true
            presentCPUDifficultyPicker(forceSelection: false)
        }
    }

    /// Эта функция вызывается, когда экран первый раз отрисовал весь свой интерфейс
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // NOTE: Устанавливаем шару радиус скругления равный половине высоты
        ballView.layer.cornerRadius = ballView.bounds.size.height / 2
        userPaddleView.layer.cornerRadius = userPaddleView.bounds.height / 2
        enemyPaddleView.layer.cornerRadius = enemyPaddleView.bounds.height / 2
        ballView.layer.shadowPath = UIBezierPath(ovalIn: ballView.bounds).cgPath
        userPaddleView.layer.shadowPath = UIBezierPath(roundedRect: userPaddleView.bounds, cornerRadius: userPaddleView.bounds.height / 2).cgPath
        enemyPaddleView.layer.shadowPath = UIBezierPath(roundedRect: enemyPaddleView.bounds, cornerRadius: enemyPaddleView.bounds.height / 2).cgPath
        backgroundGradientLayer.frame = view.bounds
    }

    /// Эта функция обрабатывает начало всех касаний экрана
    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesBegan(touches, with: event)

        // NOTE: Если нужно запустить мяч и мяч еще не был запущен - запускаем мяч
        if shouldLaunchBallOnNextTap, !hasLaunchedBall {
            hasLaunchedBall = true

            launchBall()
        }
    }

    // MARK: - Private Methods

    /// Эта функция выполняет выполняет всю конфигурацию (настройку) экрана
    ///
    /// - включает обработку жеста движения пальцем по экрану
    /// - включает динамику взаимодействия элементов
    /// - указывает что при следующем нажатии мяч должен запуститься
    ///
    private func configurePongGame() {
        if
            let savedDifficultyRawValue = UserDefaults.standard.string(forKey: DefaultsKey.cpuDifficulty),
            let savedDifficulty = CPUDifficulty(rawValue: savedDifficultyRawValue)
        {
            cpuDifficulty = savedDifficulty
        }

        // NOTE: Настраиваем лэйбл со счетом игрока
        updateUserScoreLabel()
        applyGameVisualStyle()
        configureDifficultySelectionHandling()

        // NOTE: Включаем обработку жеста движения пальцем по экрану
        self.enabledPanGestureHandling()

        // NOTE: Включаем логику платформы противника "следовать за мечом"
        self.enableEnemyPaddleFollowBehavior()

        // NOTE: Указываем, что при следующем нажатии на экран нужно запустить мяч
        self.shouldLaunchBallOnNextTap = true

        // NOTE: Начинаем проигрывать фоновую музыку
        self.backgroundSoundAudioPlayer?.prepareToPlay()
        self.backgroundSoundAudioPlayer?.play()
    }

    private func updateUserScoreLabel() {
        userScoreLabel.text = "You: \(userScore) | CPU: \(enemyScore) | Best: \(bestUserScore) | \(cpuDifficulty.title)"
    }

    private func applyGameVisualStyle() {
        backgroundGradientLayer.colors = [
            GameStyle.fieldBackgroundTopColor.cgColor,
            GameStyle.fieldBackgroundBottomColor.cgColor
        ]
        backgroundGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        backgroundGradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        backgroundGradientLayer.frame = view.bounds
        if backgroundGradientLayer.superlayer == nil {
            view.layer.insertSublayer(backgroundGradientLayer, at: 0)
        }

        lineView.backgroundColor = GameStyle.lineColor

        enemyPaddleView.backgroundColor = GameStyle.enemyPaddleColor
        enemyPaddleView.layer.cornerRadius = enemyPaddleView.bounds.height / 2
        enemyPaddleView.layer.shadowColor = GameStyle.enemyPaddleColor.cgColor
        enemyPaddleView.layer.shadowOpacity = 0.35
        enemyPaddleView.layer.shadowOffset = CGSize(width: 0, height: 4)
        enemyPaddleView.layer.shadowRadius = 10

        userPaddleView.backgroundColor = GameStyle.playerPaddleColor
        userPaddleView.layer.cornerRadius = userPaddleView.bounds.height / 2
        userPaddleView.layer.shadowColor = GameStyle.playerPaddleColor.cgColor
        userPaddleView.layer.shadowOpacity = 0.35
        userPaddleView.layer.shadowOffset = CGSize(width: 0, height: 4)
        userPaddleView.layer.shadowRadius = 10

        ballView.backgroundColor = GameStyle.ballColor
        ballView.layer.shadowColor = GameStyle.ballColor.cgColor
        ballView.layer.shadowOpacity = 0.45
        ballView.layer.shadowOffset = .zero
        ballView.layer.shadowRadius = 10

        userScoreLabel.textColor = GameStyle.scoreColor
        userScoreLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        userScoreLabel.adjustsFontSizeToFitWidth = true
        userScoreLabel.minimumScaleFactor = 0.7
        userScoreLabel.numberOfLines = 1
        userScoreLabel.layer.shadowColor = UIColor.black.cgColor
        userScoreLabel.layer.shadowOpacity = 0.35
        userScoreLabel.layer.shadowOffset = CGSize(width: 0, height: 2)
        userScoreLabel.layer.shadowRadius = 4
    }

    private func configureDifficultySelectionHandling() {
        userScoreLabel.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleScoreLabelTap)
        )
        userScoreLabel.addGestureRecognizer(tapGesture)
    }

    @objc private func handleScoreLabelTap() {
        presentCPUDifficultyPicker(forceSelection: false)
    }

    private func presentCPUDifficultyPicker(forceSelection: Bool) {
        guard presentedViewController == nil else { return }

        let alertController = UIAlertController(
            title: "CPU Difficulty",
            message: "Select challenge level",
            preferredStyle: .alert
        )

        CPUDifficulty.allCases.forEach { difficulty in
            alertController.addAction(
                UIAlertAction(title: difficulty.title, style: .default) { [weak self] _ in
                    self?.cpuDifficulty = difficulty
                }
            )
        }

        if !forceSelection {
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        }

        present(alertController, animated: true)
    }
}
