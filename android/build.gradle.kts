allprojects {
    repositories {
        google()
        mavenCentral()
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

// Samakan compileSdk seluruh subproject plugin ke 36 yang terinstal di SDK lokal.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            val libExt = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            if (libExt != null && (libExt.compileSdk ?: 0) > 36) {
                libExt.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
