#include <iostream>
#include <vector>

#include "udf/UdfLoader.h"
#include "velox/expression/SimpleFunctionRegistry.h"
#include "velox/type/Type.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: gluten_velox_joint /path/to/libhello_udf.so\n";
    return 2;
  }

  auto loader = gluten::UdfLoader::getInstance();
  loader->loadUdfLibraries(argv[1]);
  const auto sigs = loader->getRegisteredUdfSignatures();
  if (sigs.size() != 1) {
    std::cerr << "expected 1 gluten UDF signature, got " << sigs.size() << "\n";
    return 1;
  }
  const std::string name = (*sigs.begin())->name;
  if (name != "agentrl.Hello") {
    std::cerr << "unexpected UDF name: " << name << "\n";
    return 1;
  }

  loader->registerUdf();
  const auto resolved = facebook::velox::exec::simpleFunctions().resolveFunction(
      name,
      {facebook::velox::VARCHAR()});
  if (!resolved) {
    std::cerr << "Velox simple-function registry missing " << name
              << " after gluten::UdfLoader::registerUdf\n";
    return 1;
  }
  std::cout << "PASS gluten UdfLoader + Velox registry (" << name << ")\n";
  return 0;
}
