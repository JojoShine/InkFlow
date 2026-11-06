#ifndef RUNNER_AI_CREDENTIALS_H_
#define RUNNER_AI_CREDENTIALS_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
class AiCredentials {
 public:
  explicit AiCredentials(flutter::BinaryMessenger* messenger);
  ~AiCredentials();
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
