#pragma once

#include "Types.h"
#include <assimp/Importer.hpp>
#include <assimp/Exporter.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <unordered_map>
#include <chrono>

namespace converter {

class ModelConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.05f, "Loading model...");

        Assimp::Importer importer;

        // Standard post-processing — triangulate, generate normals, optimize
        unsigned int flags =
            aiProcess_Triangulate          |
            aiProcess_GenSmoothNormals     |
            aiProcess_FlipUVs              |
            aiProcess_CalcTangentSpace     |
            aiProcess_JoinIdenticalVertices|
            aiProcess_SortByPType          |
            aiProcess_OptimizeMeshes;

        const aiScene* scene = importer.ReadFile(job.inputPath.string(), flags);
        if (!scene || scene->mFlags & AI_SCENE_FLAGS_INCOMPLETE || !scene->mRootNode) {
            return ConversionResult::err(
                std::string("Assimp import failed: ") + importer.GetErrorString()
            );
        }

        if (job.onProgress) job.onProgress(0.5f, "Exporting...");

        // Map our extension to Assimp's export format ID
        const std::string& toExt = job.outputFormat.ext;
        std::string exportId     = assimpExportId(toExt);

        if (exportId.empty()) {
            return ConversionResult::err("Unsupported 3D output format: ." + toExt);
        }

        Assimp::Exporter exporter;
        aiReturn ret = exporter.Export(scene, exportId, job.outputPath.string());

        if (ret != AI_SUCCESS) {
            return ConversionResult::err(
                std::string("Assimp export failed: ") + exporter.GetErrorString()
            );
        }

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end  = std::chrono::steady_clock::now();
        double sec = std::chrono::duration<double>(end - start).count();

        ConversionResult result   = ConversionResult::ok(job.outputPath, sec);
        result.inputBytes         = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes    = fs::file_size(job.outputPath);

        // Warn user about known Assimp FBX limitations
        if (job.inputFormat.ext == "fbx" || job.outputFormat.ext == "fbx") {
            result.warnings.push_back(
                "FBX support via Assimp is limited. "
                "Complex animations and proprietary shaders may not transfer correctly."
            );
        }

        return result;
    }

private:
    // Map lowercase extension → Assimp export format string
    static std::string assimpExportId(const std::string& ext) {
        static const std::unordered_map<std::string, std::string> ids = {
            { "obj",  "obj"          },
            { "stl",  "stl"          },
            { "ply",  "ply"          },
            { "dae",  "collada"      },
            { "glb",  "glb2"         },
            { "gltf", "gltf2"        },
            { "fbx",  "fbx"          },
            { "3ds",  "3ds"          },
            { "x",    "x"            },
            { "stp",  "stp"          },
        };
        auto it = ids.find(ext);
        return it != ids.end() ? it->second : "";
    }
};

} // namespace converter
