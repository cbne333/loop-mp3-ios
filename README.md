# Loop MP3

한 곡 반복과 재생 목록 전체 반복에 집중한 iPhone용 SwiftUI 앱 초안입니다.
최소 iOS 16, Xcode 15 이상을 대상으로 작성했습니다. 외부 라이브러리나 서버는 필요하지 않습니다.

**Windows에서 무료로 사용하는 경우:** [무료 설치 안내](WINDOWS-INSTALL.md)를 먼저 읽어 주세요.
`Build IPA for free sideloading` 워크플로로 클라우드에서 iPhone용 IPA를 만든 뒤,
Windows의 Sideloadly에서 무료 Apple 계정으로 서명·설치하는 경로입니다.
7일마다 서명 갱신이 필요하며, 클라우드 빌드는 GitHub 무료 범위 안에서 실행해야 합니다.
IPA 생성과 실기기 설치는 아직 실행하지 않았습니다.
별도의 `Check iOS build` 워크플로는 시뮬레이터 컴파일 검사용입니다.

## 포함된 기능

- 파일 앱에서 MP3 여러 개 가져오기. 파일을 앱 내부로 복사하므로 가져온 뒤에는 원본 위치에 의존하지 않습니다.
- 한 곡 반복: 선택한 곡을 계속 재생합니다. 최초 실행 시 기본 설정입니다.
- 목록 반복: 표시된 순서대로 재생하고 마지막 곡 이후 첫 곡으로 돌아갑니다.
- 반복 끔: 목록을 한 차례 재생한 뒤 멈춥니다.
- 재생, 일시 정지, 이전 곡, 다음 곡, 재생 위치 이동.
- 목록 편집: 순서 변경, 삭제. 목록과 반복 설정은 앱 재실행 시 복원합니다.
- 백그라운드 오디오 설정과 잠금 화면 재생 제어.
- 전화 등 오디오 중단 처리와 이어폰 연결 해제 시 일시 정지.
- 한국어 화면, 시스템 다크 모드 및 VoiceOver 레이블.

## Mac에서 열기

1. 압축을 풀고 `LoopMP3.xcodeproj`를 Xcode에서 엽니다. `Package.swift`는 반복 로직 테스트용입니다.
2. 실행 대상을 iPhone 시뮬레이터로 고른 뒤 Run(⌘R)을 누릅니다.
3. 실제 iPhone에 설치하려면 앱 타깃 → Signing & Capabilities에서 자신의 Team을 선택합니다.
4. Bundle Identifier의 `com.example.LoopMP3`를 본인이 사용할 고유 식별자로 바꿉니다.
5. iPhone을 연결하고 필요한 기기 신뢰 및 개발자 모드 설정을 마친 다음 해당 기기로 Run을 실행합니다.
6. 앱에서 `+`를 누르고 파일 앱에 있는 MP3를 선택합니다. 곡을 누르면 재생합니다.

이 ZIP은 설치용 IPA가 아니라 소스 프로젝트입니다. iOS 빌드에는 로컬 또는 클라우드의 Mac과 Xcode가 필요합니다.
개발용 설치와 App Store 배포는 별도이며, 이 초안에는 배포용 앱 아이콘 및 스토어 제출 자료가 포함되어 있지 않습니다.

## 반복 방식과 버튼 동작

| 설정 | 곡이 끝날 때 | 마지막 곡이 끝날 때 |
|---|---|---|
| 반복 끔 | 다음 곡 | 정지 |
| 한 곡 반복 | 같은 곡 | 같은 곡 |
| 목록 반복 | 다음 곡 | 첫 곡 |

`다음 곡`은 한 곡 반복 중에도 다음 곡으로 이동합니다. 목록 반복 상태에서만 마지막 곡에서 첫 곡으로 이동합니다.
`이전 곡`은 재생 위치가 3초를 넘으면 현재 곡의 처음으로 이동합니다. 그 외에는 이전 곡으로 이동합니다.
재생 중인 곡을 삭제하면 재생을 멈춥니다. 삭제는 앱 내부 복사본에만 적용하며 원본 파일은 건드리지 않습니다.
같은 파일을 여러 번 가져오면 각각 별도 항목으로 추가됩니다.
앱을 다시 열면 목록과 반복 설정이 유지되지만 재생이 자동으로 시작되거나 이전 재생 위치가 복원되지는 않습니다.
MP3 인코딩 지연과 파일 전환으로 인한 틈까지 제거하는 무간격 재생은 보장하지 않습니다.

## 검증 상태

Windows 작업 환경에서 프로젝트의 파일 참조, XML 설정, 소스 포함 여부를 정적으로 점검했습니다.
이 환경에는 Swift 및 Xcode가 없어 컴파일, 자동 테스트 실행, 시뮬레이터와 iPhone 실기기 검증은 하지 못했습니다.
아래 명령과 체크리스트를 Mac에서 실행해야 합니다. 런타임 동작은 아직 확인되지 않았습니다.

반복 순서 로직 테스트:

```sh
cd LoopMP3
swift test
```

시뮬레이터 SDK 빌드:

```sh
xcodebuild -project LoopMP3.xcodeproj -scheme LoopMP3 \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

테스트는 `Tests/RepeatModeTests.swift`에 있으며 한 곡 반복, 목록을 두 바퀴 도는 순서, 반복 끔의 정지,
다음 곡 버튼, 빈 목록과 한 곡짜리 목록을 확인합니다. 오디오 재생 자체의 통합 테스트는 아닙니다.

실기기 확인 항목:

- [ ] 짧은 MP3 3개를 가져오고 각각 정상 재생되는지 확인.
- [ ] 한 곡 반복에서 곡이 두 번 이상 반복되는지 확인.
- [ ] 목록 반복에서 1→2→3→1 순서가 유지되는지 확인.
- [ ] 반복 끔에서 마지막 곡 이후 정지하는지 확인.
- [ ] 재생 도중 세 가지 반복 설정을 바꾸고 곡 끝에서 반영되는지 확인.
- [ ] 화면을 잠근 뒤에도 곡이 바뀌고 반복되는지 확인.
- [ ] 잠금 화면 재생/일시 정지/이전/다음/위치 이동 확인.
- [ ] 전화, Siri 등 중단 및 이어폰 연결 해제 후 동작 확인.
- [ ] 곡 순서를 바꾼 뒤 새 순서로 재생되는지 확인.
- [ ] 현재 곡 삭제 및 모든 곡 삭제 시 오류 없이 멈추는지 확인.
- [ ] 앱 종료 후 다시 열어 목록과 반복 설정 확인.
- [ ] iCloud 파일, 손상된 MP3, 긴 파일명, 큰 글자 크기 확인.

## 구현 참고

오디오 엔진은 AVAudioPlayer입니다. 한 곡 반복은 `numberOfLoops = -1`,
목록 반복은 재생 완료 콜백에서 다음 항목을 선택하도록 구성했습니다.
사용자가 선택한 파일은 보안 범위 접근 권한 내에서 읽고, 파일 제공자 읽기를 조정한 다음 내부 저장소로 복사합니다.

- [Apple: AVAudioPlayer.numberOfLoops](https://developer.apple.com/documentation/avfaudio/avaudioplayer/numberofloops)
- [Apple: SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:))
- [Apple: AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)
