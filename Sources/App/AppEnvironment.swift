struct AppEnvironment {
    let configurationStore: ConfigurationStore
    let fixTextUseCase: FixTextUseCaseProtocol
    let runtime: AppRuntime

    static func live() -> AppEnvironment {
        let configurationStore = JSONConfigurationStore()

        return AppEnvironment(
            configurationStore: configurationStore,
            fixTextUseCase: DeferredFixTextUseCase(),
            runtime: LiveAppRuntime()
        )
    }
}
