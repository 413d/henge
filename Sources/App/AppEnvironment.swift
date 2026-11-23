struct AppEnvironment {
    let configurationStore: ConfigurationStore
    let fixTextUseCase: FixTextUseCaseProtocol
    let runtime: AppRuntime
    let loginItemManager: LoginItemManaging

    init(
        configurationStore: ConfigurationStore,
        fixTextUseCase: FixTextUseCaseProtocol,
        runtime: AppRuntime,
        loginItemManager: LoginItemManaging
    ) {
        self.configurationStore = configurationStore
        self.fixTextUseCase = fixTextUseCase
        self.runtime = runtime
        self.loginItemManager = loginItemManager
    }

    static func live() -> AppEnvironment {
        let configurationStore = JSONConfigurationStore()
        let runtime = LiveAppRuntime()
        let loginItemManager = SMAppServiceLoginItemManager()
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: runtime.layoutMapper,
            casePreserver: DefaultCasePreserver()
        )

        return AppEnvironment(
            configurationStore: configurationStore,
            fixTextUseCase: LiveFixTextUseCase(
                runtime: runtime,
                transformer: transformer
            ),
            runtime: runtime,
            loginItemManager: loginItemManager
        )
    }
}
