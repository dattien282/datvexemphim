allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Chuyển thư mục build ra ngoài project root (../../build) - đây là cấu hình
// chuẩn mọi project Flutter đều cần để `flutter build`/`flutter run` tìm
// đúng APK tại <root>/build/app/outputs/flutter-apk/. Thiếu đoạn này, Gradle
// build ra APK bình thường nhưng nằm trong android/app/build/ (không phải
// <root>/build/), khiến Flutter báo "failed to produce an .apk file" dù
// build Gradle thực chất đã thành công.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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