allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Fix for isar_flutter_libs missing namespace (AGP 8+ compatibility)
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                val androidExtension = androidExt as? com.android.build.gradle.BaseExtension
                if (androidExtension != null && androidExtension.namespace == null) {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifest = groovy.xml.XmlParser().parse(manifestFile)
                        val pkg = manifest.attribute("package")
                        if (pkg != null) {
                            androidExtension.namespace = pkg.toString()
                        }
                    }
                }
            }
        }
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
