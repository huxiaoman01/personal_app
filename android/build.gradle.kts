allprojects {
    repositories {
        // 同上，只用国内镜像，避免回退到几 KB/s 的官方源。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        // Flutter 引擎的原生库（libflutter.so，分 arm64 / armeabi-v7a / x86_64）
        // 不在公共 Maven 仓库里，由 Flutter 单独托管，必须显式声明。
        //
        // 顺序很重要：Gradle 碰到仓库「报错」（超时、502）会中止整个解析，
        // 而不是继续试下一个。所以能用的源必须排在会报错的源前面。
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
