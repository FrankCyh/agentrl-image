#include <velox/functions/Macros.h>
#include <velox/functions/Registerer.h>
#include "udf/Udf.h"
#include "udf/examples/UdfCommon.h"

using namespace facebook::velox;
using namespace facebook::velox::exec;

namespace {

template <typename T>
struct HelloFunction {
  VELOX_DEFINE_FUNCTION_TYPES(T);
  static const bool allowTypeConversion = true;

  bool callNullable(out_type<Varchar>& result, const arg_type<Varchar>* input) {
    if (input == nullptr) {
      return false;
    }
    result.append(StringView("Hello, "));
    result.append(StringView(input->data(), input->size()));
    return true;
  }
};

class HelloRegisterer : public gluten::UdfRegisterer {
  int getNumUdf() override { return 1; }

  void populateUdfEntries(int& index, gluten::UdfEntry* udfEntries) override {
    udfEntries[index].name = kName;
    udfEntries[index].dataType = "varchar";
    udfEntries[index].numArgs = 1;
    udfEntries[index].argTypes = argTypes_;
    udfEntries[index].variableArity = false;
    udfEntries[index].allowTypeConversion = true;
    index++;
  }

  void registerSignatures() override {
    registerFunction<HelloFunction, Varchar, Varchar>({kName});
  }

  static constexpr const char* kName = "agentrl.Hello";
  const char* argTypes_[1] = {"varchar"};
};

std::vector<std::shared_ptr<gluten::UdfRegisterer>>& registers() {
  static std::vector<std::shared_ptr<gluten::UdfRegisterer>> r;
  return r;
}

void setup() {
  static bool inited = false;
  if (inited) {
    return;
  }
  registers().push_back(std::make_shared<HelloRegisterer>());
  inited = true;
}

}  // namespace

DEFINE_GET_NUM_UDF {
  setup();
  int n = 0;
  for (const auto& r : registers()) {
    n += r->getNumUdf();
  }
  return n;
}

DEFINE_GET_UDF_ENTRIES {
  setup();
  int i = 0;
  for (const auto& r : registers()) {
    r->populateUdfEntries(i, udfEntries);
  }
}

DEFINE_REGISTER_UDF {
  setup();
  for (const auto& r : registers()) {
    r->registerSignatures();
  }
}
