struct AppEnvironment {
    let configurationStore: ConfigurationStore
    let fixTextUseCase: FixTextUseCaseProtocol
    let runtime: AppRuntime
    let loginItemManager: LoginItemManaging
    let fixStatusChannel: FixTextStatusChannel

    init(
        configurationStore: ConfigurationStore,
        fixTextUseCase: FixTextUseCaseProtocol,
        runtime: AppRuntime,
        loginItemManager: LoginItemManaging,
        fixStatusChannel: FixTextStatusChannel = FixTextStatusChannel()
    ) {
        self.configurationStore = configurationStore
        self.fixTextUseCase = fixTextUseCase
        self.runtime = runtime
        self.loginItemManager = loginItemManager
        self.fixStatusChannel = fixStatusChannel
    }

    static func live() -> AppEnvironment {
        let configurationStore = JSONConfigurationStore()
        let runtime = LiveAppRuntime()
        let loginItemManager = SMAppServiceLoginItemManager()
        let fixStatusChannel = FixTextStatusChannel()
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: runtime.layoutMapper,
            casePreserver: DefaultCasePreserver()
        )

        return AppEnvironment(
            configurationStore: configurationStore,
            fixTextUseCase: LiveFixTextUseCase(
                runtime: runtime,
                transformer: transformer,
                statusChannel: fixStatusChannel
            ),
            runtime: runtime,
            loginItemManager: loginItemManager,
            fixStatusChannel: fixStatusChannel
        )
    }
}
