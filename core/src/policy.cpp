#include "policy.hpp"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <stdexcept>

#include <onnxruntime_cxx_api.h>

namespace dz {

struct Policy::Impl {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "douzero"};
    std::vector<Ort::Session> sessions;
};

const char* Policy::model_name(int index) { return index == BID_MODEL ? "bid" : position_name(index); }

Policy::Policy(const std::array<std::vector<char>, 4>& models) : impl_(std::make_unique<Impl>()) {
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(1);
    opts.SetInterOpNumThreads(1);
    for (const auto& bytes : models)
        impl_->sessions.emplace_back(impl_->env, bytes.data(), bytes.size(), opts);
}

Policy::~Policy() = default;

std::unique_ptr<Policy> Policy::from_dir(const std::string& dir) {
    std::array<std::vector<char>, 4> models;
    for (int i = 0; i < 4; ++i) {
        std::string path = dir + "/" + model_name(i) + ".onnx";
        std::ifstream f(path, std::ios::binary);
        if (!f) throw std::runtime_error("cannot open " + path);
        models[i].assign(std::istreambuf_iterator<char>(f), {});
    }
    return std::make_unique<Policy>(models);
}

std::vector<float> Policy::evaluate(const GameEnv& env) {
    Observation obs = encode(env);
    auto mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 3> z_shape{obs.n, 5, 162};
    const std::array<int64_t, 2> x_shape{obs.n, obs.x_dim};
    std::array<Ort::Value, 2> inputs{
        Ort::Value::CreateTensor<float>(mem, obs.z.data(), obs.z.size(), z_shape.data(), z_shape.size()),
        Ort::Value::CreateTensor<float>(mem, obs.x.data(), obs.x.size(), x_shape.data(), x_shape.size()),
    };
    const char* input_names[] = {"z", "x"};
    const char* output_names[] = {"values"};
    auto out = impl_->sessions[env.acting()].Run(Ort::RunOptions{nullptr}, input_names, inputs.data(),
                                                 inputs.size(), output_names, 1);
    const float* values = out[0].GetTensorData<float>();
    return {values, values + obs.n};
}

Move Policy::act(const GameEnv& env) {
    const auto& legal = env.legal();
    if (legal.size() == 1) return legal[0];
    auto values = evaluate(env);
    return legal[std::max_element(values.begin(), values.end()) - values.begin()];
}

float Policy::bid_score(const Move& hand) {
    // 4x15 matrix, columns 3..A, 2, 小王, 大王; row r set if the hand holds more than r.
    std::array<float, 60> x{};
    for (int rank : hand) {
        int col = rank == 30 ? 14 : rank == 20 ? 13 : rank == 17 ? 12 : rank - 3;
        int row = 0;
        while (x[row * 15 + col] != 0) ++row;
        x[row * 15 + col] = 1;
    }
    auto mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 2> shape{1, 60};
    Ort::Value input = Ort::Value::CreateTensor<float>(mem, x.data(), x.size(), shape.data(), shape.size());
    const char* input_names[] = {"x"};
    const char* output_names[] = {"score"};
    auto out = impl_->sessions[BID_MODEL].Run(Ort::RunOptions{nullptr}, input_names, &input, 1, output_names, 1);
    return out[0].GetTensorData<float>()[0];
}

}  // namespace dz
