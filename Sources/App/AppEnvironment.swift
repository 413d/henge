struct AppEnvironment {
    let configurationStore: ConfigurationStore
    let fixTextUseCase: FixTextUseCaseProtocol
    let runtime: AppRuntime

    static func live() -> AppEnvironment {
        let configurationStore = JSONConfigurationStore()
        let runtime = LiveAppRuntime()
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: runtime.layoutMapper,
            casePreserver: DefaultCasePreserver()
        )

        return AppEnvironment(
            configurationStore: configurationStore,
            fixTextUseCase: LiveFixTextUseCase(runtime: runtime, transformer: transformer),
            runtime: runtime
        )
    }
}
