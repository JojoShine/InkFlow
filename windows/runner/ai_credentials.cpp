#include "ai_credentials.h"
#include <windows.h>
#include <wincred.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <string>
AiCredentials::AiCredentials(flutter::BinaryMessenger* messenger) {
  using Value=flutter::EncodableValue;
  channel_=std::make_unique<flutter::MethodChannel<Value>>(messenger,"inkflow/ai-credentials",&flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](const flutter::MethodCall<Value>& call,std::unique_ptr<flutter::MethodResult<Value>> result){
    const auto* args=call.arguments()?std::get_if<flutter::EncodableMap>(call.arguments()):nullptr;
    if(!args){result->Error("invalid","凭据标识不合法");return;}
    const auto found=args->find(Value("id"));
    const auto* id=found==args->end()?nullptr:std::get_if<std::string>(&found->second);
    if(!id||id->size()!=64||!std::all_of(id->begin(),id->end(),[](char c){return(c>='a'&&c<='f')||(c>='0'&&c<='9');})){result->Error("invalid","凭据标识不合法");return;}
    const auto name=std::string("InkFlow.AI.")+*id;
    std::wstring target(name.begin(),name.end());
    if(call.method_name()=="read"||call.method_name()=="contains"){
      PCREDENTIALW credential=nullptr;
      if(CredReadW(target.c_str(),CRED_TYPE_GENERIC,0,&credential)){
        if(call.method_name()=="contains"){const bool exists=credential->CredentialBlobSize>0;CredFree(credential);result->Success(Value(exists));return;}
        std::string key(reinterpret_cast<char*>(credential->CredentialBlob),credential->CredentialBlobSize);
        CredFree(credential);result->Success(Value(key));return;
      }
      if(GetLastError()==ERROR_NOT_FOUND){if(call.method_name()=="contains")result->Success(Value(false));else result->Success();return;}
    }else if(call.method_name()=="delete"){
      if(CredDeleteW(target.c_str(),CRED_TYPE_GENERIC,0)||GetLastError()==ERROR_NOT_FOUND){result->Success();return;}
    }else if(call.method_name()=="write"){
      const auto item=args->find(Value("key"));const auto* key=item==args->end()?nullptr:std::get_if<std::string>(&item->second);
      if(!key||key->empty()||key->size()>CRED_MAX_CREDENTIAL_BLOB_SIZE){result->Error("invalid","API Key 长度不可用");return;}
      CREDENTIALW credential={};credential.Type=CRED_TYPE_GENERIC;credential.TargetName=target.data();
      credential.CredentialBlobSize=static_cast<DWORD>(key->size());credential.CredentialBlob=reinterpret_cast<LPBYTE>(const_cast<char*>(key->data()));
      credential.Persist=CRED_PERSIST_LOCAL_MACHINE;
      if(CredWriteW(&credential,0)){result->Success();return;}
    }else{result->NotImplemented();return;}
    result->Error("credential_storage","系统凭据访问失败，请重试");
  });
}
AiCredentials::~AiCredentials(){channel_->SetMethodCallHandler(nullptr);}
