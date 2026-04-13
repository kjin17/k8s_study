# Git & GitHub 기초 교육

> **Git**의 개념부터 **GitHub** 계정 생성, 기본 명령어, 브랜치 전략, 협업 워크플로우까지
> 처음 접하는 분을 대상으로 작성되었습니다.

---

## 목차

1. [Git이란 무엇인가?](#1-git이란-무엇인가)
2. [Git을 왜 사용하는가?](#2-git을-왜-사용하는가)
3. [Git의 핵심 개념](#3-git의-핵심-개념)
4. [GitHub 계정 생성 및 초기 설정](#4-github-계정-생성-및-초기-설정)
5. [Git 설치 및 초기 설정](#5-git-설치-및-초기-설정)
6. [저장소 만들기](#6-저장소-만들기)
7. [기본 워크플로우: add → commit → push](#7-기본-워크플로우-add--commit--push)
8. [파일 상태 확인과 변경 이력 조회](#8-파일-상태-확인과-변경-이력-조회)
9. [브랜치](#9-브랜치)
10. [원격 저장소 연동](#10-원격-저장소-연동)
11. [병합과 충돌 해결](#11-병합과-충돌-해결)
12. [Pull Request (PR)](#12-pull-request-pr)
13. [되돌리기](#13-되돌리기)
14. [태그](#14-태그)
15. [.gitignore](#15-gitignore)
16. [자주 쓰는 명령어 요약](#16-자주-쓰는-명령어-요약)
17. [Git 브랜치 전략](#17-git-브랜치-전략)
18. [팁과 모범 사례](#18-팁과-모범-사례)

---

## 1. Git이란 무엇인가?

### 한 문장 정의

> **Git**은 파일의 변경 이력을 추적하고 여러 사람이 동시에 작업할 수 있게 해주는
> **분산 버전 관리 시스템(DVCS)** 입니다.

### 비유로 이해하기

```
┌────────────────────────────────────────────────────────┐
│              문서 작업에 비유하면...                       │
│                                                        │
│  [Git 없이]                    [Git 사용]               │
│                                                        │
│  보고서_최종.docx               commit 1: "초안 작성"    │
│  보고서_최종_수정.docx           commit 2: "표 추가"     │
│  보고서_최종_진짜최종.docx       commit 3: "오타 수정"    │
│  보고서_최종_진짜최종2.docx      commit 4: "검토 반영"    │
│                                                        │
│  → 어떤 파일이 최신인지 모름      → 모든 변경 이력이 깔끔  │
│  → 이전 버전 복구 불가능          → 언제든 과거로 되돌리기  │
│  → 누가 뭘 바꿨는지 모름         → 누가, 언제, 왜 바꿨는지│
└────────────────────────────────────────────────────────┘
```

### Git vs GitHub

| 항목 | Git | GitHub |
|------|-----|--------|
| 정체 | 버전 관리 **소프트웨어** | Git 저장소 **호스팅 서비스** |
| 설치 | 로컬 컴퓨터에 설치 | 웹 브라우저로 접속 |
| 역할 | 변경 이력 추적, 브랜치, 병합 | 원격 저장소, 협업, PR, 이슈 관리 |
| 비유 | 동영상 편집 프로그램 | YouTube (영상을 올리고 공유하는 곳) |
| 경쟁 | — | GitLab, Bitbucket, Gitea |
| 비용 | 완전 무료 (오픈소스) | 무료 플랜 + 유료 플랜 |

---

## 2. Git을 왜 사용하는가?

### 버전 관리가 필요한 이유

```
[혼자 작업할 때]

  시간 ────────────────────────────────────────→
  │
  │  v1 ─── v2 ─── v3 ─── v4 (현재)
  │                  │
  │                  └─── "v3 상태로 되돌리고 싶다"  → Git이 해결
  │
```

```
[여러 명이 작업할 때]

  철수: ──── A ──── B ──── C
                          ↘
  영희: ──── A ──── D ──── 합치기(Merge)  → Git이 자동 병합
                          ↗
  민수: ──── A ──── E ──── F
```

### Git이 해결하는 핵심 문제

| 문제 | Git 없이 | Git 사용 |
|------|----------|----------|
| 버전 관리 | 파일명에 날짜/번호 붙이기 | 커밋 이력으로 자동 관리 |
| 협업 | 이메일로 파일 주고받기 | 원격 저장소에서 동기화 |
| 백업 | USB, 클라우드 수동 복사 | 원격 저장소가 자동 백업 |
| 이력 추적 | 누가 뭘 바꿨는지 모름 | `git log`, `git blame`으로 추적 |
| 실험 | 복사본 만들어서 시도 | 브랜치로 독립 작업 후 병합 |
| 복구 | 이전 버전 찾기 어려움 | `git checkout`으로 즉시 복구 |

---

## 3. Git의 핵심 개념

### 세 가지 영역

Git은 파일을 **세 가지 영역**으로 관리합니다. 이 구조를 이해하면 Git의 거의 모든 명령어를 이해할 수 있습니다.

```
┌─────────────────────────────────────────────────────────────┐
│                    Git의 세 가지 영역                         │
│                                                             │
│  ┌──────────────┐   git add   ┌──────────────┐  git commit  │
│  │  Working     │ ──────────→ │  Staging     │ ──────────→  │
│  │  Directory   │             │  Area        │              │
│  │  (작업 디렉터리)│ ←────────── │  (스테이징)   │              │
│  └──────────────┘  git restore└──────────────┘              │
│        │                                                    │
│        │  파일을 수정하는 곳       커밋할 파일을                │
│        │  (실제 폴더)             골라놓는 곳                  │
│        │                                                    │
│        │                       ┌──────────────┐             │
│        │                       │  Repository  │             │
│        │                       │  (.git)      │             │
│        │                       │              │             │
│        │                       │  커밋된 이력이  │             │
│        │                       │  영구 저장     │             │
│        │                       └──────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

### 비유

| Git 영역 | 비유 |
|----------|------|
| Working Directory | 책상 위에서 작업 중인 서류 |
| Staging Area | "이번에 제출할 서류" 봉투에 넣은 것 |
| Repository | 최종 제출 완료된 서류 보관함 |

### 핵심 용어 정리

| 용어 | 뜻 | 비유 |
|------|-----|------|
| **Repository (저장소)** | Git이 관리하는 프로젝트 폴더 | 프로젝트 보관함 |
| **Commit (커밋)** | 변경 사항을 저장소에 기록 | "이 시점을 기억해둬" 스냅샷 |
| **Branch (브랜치)** | 독립적인 작업 흐름 | 평행 세계 |
| **Merge (병합)** | 두 브랜치를 합치기 | 평행 세계를 하나로 합치기 |
| **Clone (클론)** | 원격 저장소를 로컬에 복사 | 도서관 책을 복사해 오기 |
| **Push (푸시)** | 로컬 커밋을 원격에 업로드 | 완성된 과제를 제출 |
| **Pull (풀)** | 원격 변경을 로컬에 다운로드 | 최신 자료를 받아오기 |
| **Fork (포크)** | 다른 사람 저장소를 내 계정에 복사 | 남의 레시피를 내 노트에 베껴오기 |
| **HEAD** | 현재 위치를 가리키는 포인터 | "지금 여기" 표시 |

---

## 4. GitHub 계정 생성 및 초기 설정

### 4-1. 계정 생성

```
1. https://github.com 접속
2. 우측 상단 "Sign up" 클릭
3. 이메일 주소 입력
4. 비밀번호 설정 (15자 이상 또는 숫자+소문자 8자 이상)
5. 사용자명(Username) 입력
   - 영문, 숫자, 하이픈(-) 만 사용 가능
   - 나중에 URL이 됨: github.com/<username>
   - 예: hong-gildong, developer-kim
6. 이메일 인증 완료
7. 무료 플랜(Free) 선택
```

### 4-2. 프로필 설정 (권장)

```
Settings → Profile
  - Name: 실명 또는 닉네임
  - Bio: 간단한 자기소개
  - Company: 소속 (선택)
  - Location: 위치 (선택)
```

### 4-3. SSH 키 등록 (권장)

비밀번호 입력 없이 Git 작업을 하려면 SSH 키를 등록합니다.

```bash
# 1. SSH 키 생성
ssh-keygen -t ed25519 -C "your-email@example.com"
# Enter 키를 3번 눌러 기본값 사용

# 2. 공개 키 복사
# macOS
cat ~/.ssh/id_ed25519.pub | pbcopy

# Linux
cat ~/.ssh/id_ed25519.pub
# 출력된 내용을 복사
```

```
3. GitHub에 등록
   Settings → SSH and GPG keys → New SSH key
   - Title: "My Laptop" 등 식별 가능한 이름
   - Key: 복사한 공개 키 붙여넣기
   - Add SSH key
```

```bash
# 4. 연결 테스트
ssh -T git@github.com
# Hi <username>! You've successfully authenticated ...
```

### 4-4. Personal Access Token (PAT) 생성

HTTPS 방식을 사용하거나 API 호출 시 필요합니다.

```
Settings → Developer settings → Personal access tokens → Tokens (classic)
  → Generate new token
  - Note: 용도 설명 (예: "my-laptop")
  - Expiration: 유효 기간
  - Scopes: repo (저장소 접근) 체크
  → Generate token
  → 표시된 토큰을 안전하게 보관 (다시 볼 수 없음!)
```

### GitHub 요금제 비교

| 항목 | Free | Pro | Team |
|------|------|-----|------|
| 퍼블릭 저장소 | 무제한 | 무제한 | 무제한 |
| 프라이빗 저장소 | 무제한 | 무제한 | 무제한 |
| 협업자 수 | 무제한 | 무제한 | 무제한 |
| GitHub Actions | 2,000분/월 | 3,000분/월 | 3,000분/월 |
| 주요 추가 기능 | — | 고급 코드 리뷰 | 팀 관리, SAML SSO |
| 가격 | $0 | $4/월 | $4/유저/월 |

> 개인 학습/프로젝트에는 **Free** 플랜으로 충분합니다.

---

## 5. Git 설치 및 초기 설정

### 5-1. 설치

```bash
# macOS (Xcode CLI Tools 포함)
xcode-select --install
# 또는 Homebrew
brew install git

# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y git

# CentOS / RHEL
sudo yum install -y git

# Windows
# https://git-scm.com/download/win 에서 설치 파일 다운로드
```

```bash
# 설치 확인
git --version
# git version 2.43.0
```

### 5-2. 최초 설정 (필수)

Git을 처음 사용하면 **사용자 이름**과 **이메일**을 반드시 설정해야 합니다.
이 정보가 모든 커밋에 기록됩니다.

```bash
# 사용자 이름 설정
git config --global user.name "홍길동"

# 이메일 설정 (GitHub 가입 이메일과 동일하게)
git config --global user.email "gildong@example.com"

# 기본 브랜치 이름을 main으로 설정
git config --global init.defaultBranch main

# 기본 편집기 설정 (선택)
git config --global core.editor "vim"        # vim
git config --global core.editor "nano"       # nano
git config --global core.editor "code --wait" # VS Code

# 설정 확인
git config --list
```

### --global 옵션의 의미

| 범위 | 옵션 | 적용 대상 | 설정 파일 |
|------|------|-----------|-----------|
| 시스템 | `--system` | 모든 사용자 | `/etc/gitconfig` |
| 사용자 | `--global` | 현재 사용자의 모든 저장소 | `~/.gitconfig` |
| 저장소 | `--local` (기본) | 현재 저장소만 | `.git/config` |

```bash
# 현재 설정된 값 확인
git config user.name
# 홍길동

git config user.email
# gildong@example.com
```

---

## 6. 저장소 만들기

### 6-1. 새 저장소 만들기 (git init)

로컬에서 빈 프로젝트를 시작할 때 사용합니다.

```bash
# 프로젝트 디렉터리 생성
mkdir my-project
cd my-project

# Git 저장소 초기화
git init
# Initialized empty Git repository in /home/user/my-project/.git/

# .git 폴더가 생성됨 (Git의 모든 데이터가 여기에 저장)
ls -la
# drwxr-xr-x  .git/       ← Git 메타데이터
```

### 6-2. 기존 저장소 복사하기 (git clone)

GitHub 등 원격 저장소를 로컬로 가져올 때 사용합니다.

```bash
# HTTPS 방식
git clone https://github.com/username/repository.git

# SSH 방식 (SSH 키 등록 필요)
git clone git@github.com:username/repository.git

# 특정 디렉터리 이름으로 복사
git clone https://github.com/username/repository.git my-folder

# 실행 예시
git clone https://github.com/kubernetes/kubernetes.git
# Cloning into 'kubernetes'...
# remote: Enumerating objects: 1563254, done.
# remote: Counting objects: 100% (1563254/1563254), done.
# Receiving objects: 100% (1563254/1563254), 890.12 MiB | 15.30 MiB/s, done.
```

### 6-3. GitHub에서 저장소 만들고 연결하기

```
[GitHub 웹에서]
1. 우측 상단 "+" → "New repository"
2. Repository name: my-project
3. 설명 (선택)
4. Public 또는 Private 선택
5. "Create repository" 클릭
```

```bash
# [로컬에서 — 이미 git init 한 경우]
git remote add origin https://github.com/username/my-project.git
git branch -M main
git push -u origin main
```

```bash
# [로컬에서 — 새로 시작하는 경우]
echo "# my-project" >> README.md
git init
git add README.md
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/username/my-project.git
git push -u origin main
```

---

## 7. 기본 워크플로우: add → commit → push

Git의 가장 기본적인 작업 흐름입니다.

```
┌────────────┐    git add    ┌────────────┐   git commit   ┌────────────┐   git push   ┌────────────┐
│  파일 수정  │ ───────────→ │  스테이징    │ ────────────→ │  로컬 커밋  │ ──────────→ │  원격 저장소 │
│            │              │  (준비 완료) │               │  (이력 저장) │             │  (GitHub)  │
└────────────┘              └────────────┘               └────────────┘             └────────────┘
```

### 7-1. 파일 수정

```bash
# 새 파일 생성
echo "Hello, Git!" > hello.txt

# 기존 파일 수정
vim app.py
```

### 7-2. git add — 스테이징

커밋할 파일을 **스테이징 영역**에 올립니다.

```bash
# 특정 파일 추가
git add hello.txt

# 여러 파일 추가
git add hello.txt app.py

# 현재 디렉터리의 모든 변경 파일 추가
git add .

# 특정 패턴의 파일 추가
git add *.py

# 변경된 파일만 추가 (새 파일 제외)
git add -u
```

```bash
# 실행 예시
$ git add hello.txt
$ git status
On branch main
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        new file:   hello.txt       ← 스테이징됨 (초록색)
```

### 7-3. git commit — 변경 이력 저장

스테이징된 파일을 저장소에 **영구 기록**합니다.

```bash
# 커밋 메시지와 함께 커밋
git commit -m "Add hello.txt"

# 긴 메시지 작성 (편집기 열림)
git commit

# add와 commit을 동시에 (추적 중인 파일만, 새 파일 제외)
git commit -am "Update app.py"
```

```bash
# 실행 예시
$ git commit -m "Add hello.txt with greeting message"
[main abc1234] Add hello.txt with greeting message
 1 file changed, 1 insertion(+)
 create mode 100644 hello.txt
```

#### 좋은 커밋 메시지 작성법

```
# 형식
<타입>: <무엇을 했는지 간결하게>

# 예시
feat: 사용자 로그인 기능 추가
fix: 비밀번호 검증 오류 수정
docs: README에 설치 방법 추가
refactor: 인증 모듈 구조 개선
test: 로그인 API 단위 테스트 추가
chore: 의존성 버전 업데이트
```

| 타입 | 의미 |
|------|------|
| `feat` | 새로운 기능 |
| `fix` | 버그 수정 |
| `docs` | 문서 변경 |
| `style` | 코드 포맷팅 (동작 변경 없음) |
| `refactor` | 리팩터링 (기능 변경 없음) |
| `test` | 테스트 추가/수정 |
| `chore` | 빌드, 설정 등 기타 작업 |

### 7-4. git push — 원격 저장소에 업로드

```bash
# 기본 push
git push

# 처음 push 할 때 (upstream 설정)
git push -u origin main

# 특정 브랜치 push
git push origin feature/login
```

```bash
# 실행 예시
$ git push -u origin main
Enumerating objects: 3, done.
Counting objects: 100% (3/3), done.
Writing objects: 100% (3/3), 234 bytes | 234.00 KiB/s, done.
Total 3 (delta 0), reused 0 (delta 0)
To https://github.com/username/my-project.git
 * [new branch]      main -> main
Branch 'main' set up to track remote branch 'main' from 'origin'.
```

### 전체 흐름 예시

```bash
# 1. 파일 생성/수정
echo "print('hello')" > app.py

# 2. 상태 확인
git status

# 3. 스테이징
git add app.py

# 4. 커밋
git commit -m "feat: Add main application file"

# 5. 원격에 업로드
git push
```

---

## 8. 파일 상태 확인과 변경 이력 조회

### 8-1. git status — 현재 상태 확인

```bash
git status
```

```bash
# 실행 예시 — 다양한 상태의 파일이 있을 때
$ git status
On branch main
Changes to be committed:               ← 스테이징된 파일 (초록)
  (use "git restore --staged <file>..." to unstage)
        modified:   app.py

Changes not staged for commit:          ← 수정했지만 스테이징 안 된 파일 (빨강)
  (use "git add <file>..." to update that will be committed)
        modified:   config.yaml

Untracked files:                        ← Git이 추적하지 않는 새 파일 (빨강)
  (use "git add <file>..." to include in what will be committed)
        new-feature.py
```

```bash
# 간략한 상태 보기
git status -s
# M  app.py          ← 스테이징됨(초록 M)
#  M config.yaml     ← 수정됨(빨강 M)
# ?? new-feature.py  ← 추적 안 됨
```

파일 상태 흐름:

```
┌───────────┐    git add    ┌──────────┐   git commit   ┌───────────┐
│ Untracked │ ───────────→  │ Staged   │ ────────────→  │ Committed │
│ (추적 안됨) │              │ (스테이징) │                │ (커밋 완료) │
└───────────┘              └──────────┘                └───────────┘
      ↑                         ↑                           │
      │                         │        파일 수정            │
      │                         └──────────────────────────  │
      │                                                      │
      └──────── 새 파일 생성 ──────────────────────────────────┘
```

### 8-2. git diff — 변경 내용 확인

```bash
# 작업 디렉터리 vs 스테이징 (아직 add 안 한 변경)
git diff

# 스테이징 vs 마지막 커밋 (add 했지만 commit 안 한 변경)
git diff --staged

# 두 커밋 비교
git diff abc1234 def5678

# 특정 파일의 변경만 보기
git diff app.py
```

```bash
# 실행 예시
$ git diff
diff --git a/app.py b/app.py
index abc1234..def5678 100644
--- a/app.py
+++ b/app.py
@@ -1,3 +1,4 @@
 print('hello')
+print('world')         ← 추가된 줄 (초록)
-print('old line')      ← 삭제된 줄 (빨강)
```

### 8-3. git log — 커밋 이력 조회

```bash
# 기본 로그
git log

# 한 줄로 간결하게
git log --oneline

# 그래프와 함께 (브랜치 흐름 시각화)
git log --oneline --graph --all

# 최근 5개만
git log -5

# 특정 파일의 이력
git log -- app.py

# 특정 작성자의 커밋만
git log --author="홍길동"

# 날짜 범위
git log --since="2024-01-01" --until="2024-12-31"
```

```bash
# 실행 예시 — git log --oneline --graph --all
$ git log --oneline --graph --all
* e5f6g7h (HEAD -> main) Merge branch 'feature/login'
|\
| * c3d4e5f (feature/login) feat: Add login page
| * a1b2c3d feat: Add auth module
|/
* 9z8y7x6 fix: Update README
* 7w6v5u4 Initial commit
```

### 8-4. git blame — 누가 이 줄을 작성했는가

```bash
# 파일의 각 줄을 누가 마지막으로 수정했는지 표시
git blame app.py
```

```bash
# 실행 예시
$ git blame app.py
abc1234 (홍길동  2024-03-15 10:30:00 +0900  1) print('hello')
def5678 (김영희  2024-03-16 14:20:00 +0900  2) print('world')
ghi9012 (홍길동  2024-03-17 09:15:00 +0900  3) print('done')
```

---

## 9. 브랜치

### 브랜치란?

> **브랜치**는 독립적인 작업 공간입니다.
> main 브랜치에 영향을 주지 않고 새 기능을 개발하거나 버그를 수정할 수 있습니다.

```
        feature/login
        ┌── B ── C ── D
       /                \
main: A ───────────────── E (Merge)
       \                /
        └── F ── G ────┘
        fix/typo
```

### 9-1. 브랜치 기본 명령어

```bash
# 브랜치 목록 보기
git branch
# * main              ← 현재 브랜치에 * 표시
#   feature/login

# 원격 브랜치 포함 모든 브랜치
git branch -a

# 새 브랜치 생성
git branch feature/login

# 브랜치 이동 (체크아웃)
git checkout feature/login
# Switched to branch 'feature/login'

# 생성과 동시에 이동 (자주 사용!)
git checkout -b feature/login
# Switched to a new branch 'feature/login'

# switch 명령어 (Git 2.23+, checkout 대체)
git switch feature/login
git switch -c feature/login    # 생성 + 이동

# 브랜치 삭제
git branch -d feature/login        # 병합된 브랜치만 삭제
git branch -D feature/login        # 강제 삭제

# 브랜치 이름 변경
git branch -m old-name new-name
```

```bash
# 실행 예시 — 브랜치 생성부터 작업까지
$ git checkout -b feature/login
Switched to a new branch 'feature/login'

$ echo "login page" > login.html
$ git add login.html
$ git commit -m "feat: Add login page"
[feature/login abc1234] feat: Add login page

$ git checkout main
Switched to branch 'main'
# login.html이 사라짐 (main에는 없으니까)

$ git checkout feature/login
Switched to branch 'feature/login'
# login.html이 다시 보임
```

### 9-2. 브랜치 네이밍 규칙 (권장)

| 접두사 | 용도 | 예시 |
|--------|------|------|
| `feature/` | 새 기능 개발 | `feature/user-login` |
| `fix/` | 버그 수정 | `fix/login-error` |
| `hotfix/` | 긴급 운영 수정 | `hotfix/critical-crash` |
| `release/` | 릴리스 준비 | `release/v2.1.0` |
| `docs/` | 문서 작업 | `docs/api-guide` |
| `refactor/` | 리팩터링 | `refactor/auth-module` |

---

## 10. 원격 저장소 연동

### 10-1. remote 관리

```bash
# 원격 저장소 목록
git remote -v
# origin  https://github.com/username/my-project.git (fetch)
# origin  https://github.com/username/my-project.git (push)

# 원격 저장소 추가
git remote add origin https://github.com/username/my-project.git

# 원격 저장소 URL 변경
git remote set-url origin https://github.com/username/new-repo.git

# 원격 저장소 삭제
git remote remove origin
```

### 10-2. git pull — 원격 변경 가져오기

```bash
# 현재 브랜치의 원격 변경 가져오기 + 병합
git pull

# 특정 원격/브랜치에서 가져오기
git pull origin main

# rebase 방식으로 가져오기 (이력을 깔끔하게 유지)
git pull --rebase
```

```bash
# 실행 예시
$ git pull origin main
remote: Enumerating objects: 5, done.
remote: Counting objects: 100% (5/5), done.
remote: Compressing objects: 100% (3/3), done.
Unpacking objects: 100% (3/3), done.
From https://github.com/username/my-project
 * branch            main       -> FETCH_HEAD
Updating abc1234..def5678
Fast-forward
 README.md | 2 ++
 1 file changed, 2 insertions(+)
```

### 10-3. git fetch — 원격 정보만 가져오기 (병합 안 함)

```bash
# fetch: 원격 데이터를 가져오되 로컬 파일은 건드리지 않음
git fetch origin

# 원격 브랜치 목록 확인
git branch -r

# fetch 후 수동으로 병합
git fetch origin
git merge origin/main
```

> **pull = fetch + merge** 입니다.
> 신중하게 작업하고 싶을 때는 `fetch` 후 확인하고 `merge`하는 것이 안전합니다.

### 10-4. fetch vs pull 비교

```
[git pull]                          [git fetch + merge]

원격 ──── 가져오기+병합 ──→ 로컬    원격 ──── 가져오기만 ──→ 로컬(원격추적)
        (한 번에)                                           │
                                              확인 후 ──→ merge
                                                        (수동 병합)
```

---

## 11. 병합과 충돌 해결

### 11-1. git merge — 브랜치 병합

```bash
# main 브랜치로 이동
git checkout main

# feature/login 브랜치를 main에 병합
git merge feature/login
```

#### 병합의 두 가지 방식

```
[Fast-forward Merge — 갈라진 적 없을 때]

Before:
main:          A ── B
                     \
feature/login:        C ── D

After (fast-forward):
main:          A ── B ── C ── D
```

```
[3-way Merge — 갈라진 후 양쪽 모두 커밋이 있을 때]

Before:
main:          A ── B ── E
                     \
feature/login:        C ── D

After (merge commit 생성):
main:          A ── B ── E ── M (merge commit)
                     \       /
feature/login:        C ── D
```

### 11-2. 충돌(Conflict) 해결

두 브랜치에서 **같은 파일의 같은 줄**을 서로 다르게 수정했을 때 충돌이 발생합니다.

```bash
$ git merge feature/login
Auto-merging app.py
CONFLICT (content): Merge conflict in app.py
Automatic merge failed; fix conflicts and then commit the result.
```

충돌이 발생한 파일을 열면:

```python
# app.py
print('hello')
<<<<<<< HEAD
print('main branch change')       ← 현재 브랜치(main)의 내용
=======
print('feature branch change')    ← 병합하려는 브랜치의 내용
>>>>>>> feature/login
print('done')
```

#### 해결 순서

```bash
# 1. 충돌 파일을 열어서 원하는 내용으로 수정
#    <<<<<<< , ======= , >>>>>>> 마커를 모두 삭제

# 수정 후 app.py:
print('hello')
print('feature branch change')    ← 원하는 내용만 남김
print('done')

# 2. 수정한 파일을 스테이징
git add app.py

# 3. 병합 커밋 완료
git commit -m "Merge feature/login into main (resolve conflict)"

# 4. 원격에 push
git push
```

#### 충돌 예방 팁

| 방법 | 설명 |
|------|------|
| 자주 pull 하기 | 원격 변경을 수시로 반영하여 차이를 줄임 |
| 작은 단위로 커밋 | 변경 범위를 줄여 충돌 가능성 최소화 |
| 브랜치 수명 짧게 | 오래된 브랜치일수록 충돌 가능성 높음 |
| 파일 분리 | 하나의 파일에 여러 사람이 동시 작업 피하기 |

---

## 12. Pull Request (PR)

### PR이란?

> **Pull Request**는 내가 작업한 브랜치의 변경 사항을 다른 브랜치(보통 main)에
> 병합해 달라고 **요청**하는 것입니다. 코드 리뷰, 토론, CI/CD 검증 과정을 거칩니다.

```
┌──────────────────────── PR 워크플로우 ─────────────────────────┐
│                                                                │
│  1. 브랜치 생성    git checkout -b feature/login               │
│         ↓                                                      │
│  2. 작업 & 커밋    git add . && git commit -m "..."           │
│         ↓                                                      │
│  3. 원격에 Push    git push -u origin feature/login           │
│         ↓                                                      │
│  4. PR 생성       GitHub 웹에서 "New Pull Request" 클릭        │
│         ↓                                                      │
│  5. 코드 리뷰     팀원이 코드 검토, 코멘트, 수정 요청           │
│         ↓                                                      │
│  6. 승인 & 병합   리뷰어가 Approve → Merge 클릭               │
│         ↓                                                      │
│  7. 브랜치 삭제   병합 완료 후 feature 브랜치 삭제              │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### PR 생성 방법

```bash
# 1. feature 브랜치에서 작업 완료 후 push
git checkout -b feature/login
# ... 작업 ...
git add .
git commit -m "feat: Add login page"
git push -u origin feature/login
```

```
# 2. GitHub 웹에서 PR 생성
- push 후 GitHub 저장소 페이지에 "Compare & pull request" 버튼 표시
- 또는 Pull requests 탭 → "New pull request"

# 3. PR 작성
- Title: "feat: Add login page"
- Description:
    ## 변경 사항
    - 로그인 페이지 HTML/CSS 추가
    - 로그인 API 연동

    ## 테스트
    - [x] 로컬에서 로그인 테스트 완료
    - [ ] 비밀번호 재설정 테스트

- Reviewers: 리뷰어 지정
- Labels: enhancement, frontend 등
```

### PR 병합 방식

| 방식 | 설명 | 이력 |
|------|------|------|
| **Merge commit** | 병합 커밋 생성 | 모든 커밋 보존 |
| **Squash and merge** | 모든 커밋을 하나로 합침 | 깔끔한 이력 |
| **Rebase and merge** | 커밋을 main 위에 재배치 | 선형 이력 |

```
[Merge commit]
main: A ── B ── M (merge commit)
              /
feature: C ── D

[Squash and merge]
main: A ── B ── CD (하나의 커밋으로 합쳐짐)

[Rebase and merge]
main: A ── B ── C' ── D' (재배치)
```

---

## 13. 되돌리기

### 13-1. 스테이징 취소 (add 되돌리기)

```bash
# 특정 파일 스테이징 취소
git restore --staged app.py

# 모든 파일 스테이징 취소
git restore --staged .

# 구버전 명령어 (동일 기능)
git reset HEAD app.py
```

### 13-2. 파일 수정 되돌리기 (마지막 커밋 상태로)

```bash
# 특정 파일을 마지막 커밋 상태로 복원
git restore app.py

# 구버전 명령어 (동일 기능)
git checkout -- app.py
```

> **주의:** `git restore`는 수정한 내용을 완전히 삭제합니다. 되돌릴 수 없습니다!

### 13-3. 커밋 수정

```bash
# 마지막 커밋 메시지 변경 (아직 push 하지 않은 경우)
git commit --amend -m "새로운 커밋 메시지"

# 마지막 커밋에 파일 추가 (메시지 유지)
git add forgotten-file.py
git commit --amend --no-edit
```

### 13-4. 커밋 되돌리기

```bash
# revert: 이전 커밋을 취소하는 "새 커밋" 생성 (안전, 권장)
git revert abc1234

# reset --soft: 커밋만 취소 (변경 내용은 스테이징에 유지)
git reset --soft HEAD~1

# reset --mixed: 커밋 + 스테이징 취소 (변경 내용은 작업 디렉터리에 유지, 기본값)
git reset HEAD~1

# reset --hard: 모두 삭제 (변경 내용 완전 삭제, 위험!)
git reset --hard HEAD~1
```

```
┌─────────────────────────────────────────────────────┐
│                reset 옵션 비교                        │
│                                                     │
│  --soft     커밋 취소  /  스테이징 유지  /  파일 유지   │
│  --mixed    커밋 취소  /  스테이징 취소  /  파일 유지   │
│  --hard     커밋 취소  /  스테이징 취소  /  파일 삭제   │
│                                                     │
│  ⚠ --hard 는 되돌릴 수 없습니다! 신중하게 사용하세요.   │
└─────────────────────────────────────────────────────┘
```

### revert vs reset

| 항목 | revert | reset |
|------|--------|-------|
| 방식 | 취소 커밋을 새로 생성 | 커밋 이력 자체를 삭제 |
| 이력 | 보존됨 (안전) | 삭제됨 (위험) |
| 공유 브랜치 | 사용 가능 | 사용 금지 (타인 이력 꼬임) |
| 권장 상황 | push 완료된 커밋 | 아직 push 하지 않은 로컬 커밋 |

---

## 14. 태그

### 태그란?

> 특정 커밋에 붙이는 **이름표**입니다. 주로 릴리스 버전을 표시할 때 사용합니다.

```bash
# 태그 목록
git tag
# v1.0.0
# v1.1.0
# v2.0.0

# 태그 생성 (Annotated — 권장)
git tag -a v1.0.0 -m "첫 번째 정식 릴리스"

# 태그 생성 (Lightweight — 간단)
git tag v1.0.0

# 특정 커밋에 태그
git tag -a v0.9.0 -m "베타 릴리스" abc1234

# 태그 상세 정보
git show v1.0.0

# 태그를 원격에 push
git push origin v1.0.0

# 모든 태그 push
git push origin --tags

# 태그 삭제
git tag -d v1.0.0                  # 로컬
git push origin --delete v1.0.0    # 원격
```

```bash
# 실행 예시
$ git tag -a v1.0.0 -m "First stable release"
$ git push origin v1.0.0
Total 0 (delta 0), reused 0 (delta 0)
To https://github.com/username/my-project.git
 * [new tag]         v1.0.0 -> v1.0.0
```

> GitHub에서 태그를 push하면 자동으로 **Releases** 페이지에 표시됩니다.

---

## 15. .gitignore

### .gitignore란?

> Git이 **추적하지 않을 파일/폴더**를 지정하는 설정 파일입니다.
> 비밀번호, 빌드 결과물, OS 임시 파일 등을 제외할 때 사용합니다.

### 작성 방법

```bash
# .gitignore 파일을 프로젝트 루트에 생성
vim .gitignore
```

```gitignore
# 주석은 # 으로 시작

# 특정 파일
.env
secrets.yaml
credentials.json

# 특정 확장자
*.log
*.tmp
*.pyc

# 특정 폴더
node_modules/
__pycache__/
.vscode/
.idea/
dist/
build/

# 예외 (! 로 추적 대상에 다시 포함)
!important.log

# 특정 경로의 파일만
/config/local.yaml

# 와일드카드
*.secret.*
temp-*
```

### 언어/프레임워크별 .gitignore 예시

```gitignore
# ── Python ──
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/

# ── Node.js ──
node_modules/
npm-debug.log
.env

# ── Java ──
*.class
target/
*.jar

# ── Go ──
*.exe
vendor/

# ── 공통 ──
.DS_Store          # macOS
Thumbs.db          # Windows
*.swp              # Vim
.env               # 환경 변수 (비밀번호 등)
```

> **이미 추적 중인 파일**은 `.gitignore`에 추가해도 무시되지 않습니다.
> 추적을 중단하려면:

```bash
# 파일을 Git 추적에서 제거 (로컬 파일은 유지)
git rm --cached .env
git commit -m "chore: Remove .env from tracking"
```

> GitHub에서 다양한 `.gitignore` 템플릿을 제공합니다:
> https://github.com/github/gitignore

---

## 16. 자주 쓰는 명령어 요약

### 기본 명령어

| 명령어 | 설명 |
|--------|------|
| `git init` | 새 저장소 초기화 |
| `git clone <url>` | 원격 저장소 복사 |
| `git status` | 현재 상태 확인 |
| `git add <file>` | 스테이징 |
| `git commit -m "msg"` | 커밋 |
| `git push` | 원격에 업로드 |
| `git pull` | 원격 변경 가져오기 |

### 브랜치 명령어

| 명령어 | 설명 |
|--------|------|
| `git branch` | 브랜치 목록 |
| `git branch <name>` | 브랜치 생성 |
| `git checkout <name>` | 브랜치 이동 |
| `git checkout -b <name>` | 생성 + 이동 |
| `git merge <name>` | 브랜치 병합 |
| `git branch -d <name>` | 브랜치 삭제 |

### 조회 명령어

| 명령어 | 설명 |
|--------|------|
| `git log` | 커밋 이력 |
| `git log --oneline` | 한 줄 이력 |
| `git log --graph --all` | 그래프 이력 |
| `git diff` | 변경 내용 비교 |
| `git blame <file>` | 줄별 작성자 확인 |
| `git show <commit>` | 특정 커밋 상세 |

### 되돌리기 명령어

| 명령어 | 설명 |
|--------|------|
| `git restore <file>` | 파일 수정 되돌리기 |
| `git restore --staged <file>` | 스테이징 취소 |
| `git revert <commit>` | 커밋 되돌리기 (새 커밋 생성) |
| `git reset --soft HEAD~1` | 커밋 취소 (변경 유지) |
| `git reset --hard HEAD~1` | 커밋 + 변경 모두 삭제 |

### 원격 명령어

| 명령어 | 설명 |
|--------|------|
| `git remote -v` | 원격 저장소 목록 |
| `git remote add <name> <url>` | 원격 추가 |
| `git fetch` | 원격 정보 가져오기 (병합 X) |
| `git push -u origin <branch>` | 브랜치 최초 push |
| `git push origin --delete <branch>` | 원격 브랜치 삭제 |

---

## 17. Git 브랜치 전략

팀에서 Git을 효과적으로 사용하기 위한 브랜치 관리 전략입니다.

### 17-1. GitHub Flow (단순, 권장)

소규모 팀이나 지속적 배포(CD) 환경에 적합합니다.

```
main ────── A ─────── B ─────── C ─────── D ──────→ (항상 배포 가능)
              \               /  \               /
feature/login  └── E ── F ──┘    └── G ── H ──┘
                                feature/profile
```

**규칙:**
1. `main`은 항상 배포 가능한 상태
2. 작업은 반드시 브랜치에서 진행
3. PR을 통해 코드 리뷰 후 병합
4. 병합 후 즉시 배포

### 17-2. Git Flow (복잡, 릴리스 주기가 있는 프로젝트)

```
main ────── v1.0 ──────────────────────── v2.0 ──→
              │                            ↑
develop ──────┼── A ── B ── C ── D ── E ───┤──→
              │        \       /           │
feature/      │         └─ F ─┘            │
              │                            │
release/      │              ┌── G ── H ───┘
              │              │ (버그 수정만)
hotfix/       └── X ─────────┘
              (긴급 수정)
```

| 브랜치 | 용도 | 생성 기준 | 병합 대상 |
|--------|------|-----------|-----------|
| `main` | 운영 배포 코드 | — | — |
| `develop` | 개발 통합 | main | main (릴리스 시) |
| `feature/*` | 기능 개발 | develop | develop |
| `release/*` | 릴리스 준비 | develop | main + develop |
| `hotfix/*` | 긴급 수정 | main | main + develop |

### 어떤 전략을 선택할까?

| 상황 | 권장 전략 |
|------|-----------|
| 소규모 팀, 빠른 배포 | GitHub Flow |
| 중대형 팀, 정기 릴리스 | Git Flow |
| 개인 프로젝트 | GitHub Flow (또는 main 직접 push) |
| 오픈소스 기여 | Fork → PR |

---

## 18. 팁과 모범 사례

### 커밋 관련

```
✅ 좋은 습관
  • 작은 단위로 자주 커밋 (하나의 커밋 = 하나의 변경)
  • 의미 있는 커밋 메시지 작성
  • 동작하는 상태에서 커밋 (빌드 깨진 상태로 커밋 금지)

❌ 나쁜 습관
  • "fix", "update", "작업중" 같은 모호한 메시지
  • 여러 기능을 하나의 커밋에 섞기
  • 하루치 작업을 한 번에 커밋
```

### 브랜치 관련

```
✅ 좋은 습관
  • main에 직접 push 하지 않기 (PR 사용)
  • 브랜치 이름에 목적 명시 (feature/login, fix/typo)
  • 병합 후 브랜치 삭제
  • 작업 전 항상 git pull 로 최신 상태 유지

❌ 나쁜 습관
  • 하나의 브랜치에서 여러 기능 동시 개발
  • 브랜치를 오래 유지 (오래될수록 충돌 가능성 증가)
  • 의미 없는 브랜치 이름 (branch1, test, temp)
```

### 보안 관련

```
⚠ 절대 커밋하면 안 되는 것들
  • 비밀번호, API 키, 토큰
  • .env 파일
  • 인증서 (*.pem, *.key)
  • credentials.json 같은 인증 정보

  → .gitignore 에 반드시 추가
  → 실수로 커밋했다면 이력에서도 제거 필요:
    git filter-branch 또는 BFG Repo-Cleaner 사용
```

### 유용한 Git 설정

```bash
# 자주 쓰는 명령어 별칭(alias) 설정
git config --global alias.st "status"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.ci "commit"
git config --global alias.lg "log --oneline --graph --all"

# 사용 예시
git st       # = git status
git co main  # = git checkout main
git lg       # = git log --oneline --graph --all

# 컬러 출력 활성화
git config --global color.ui auto

# 줄바꿈 자동 처리 (Windows/Mac 혼용 환경)
# Windows
git config --global core.autocrlf true
# macOS/Linux
git config --global core.autocrlf input

# 기본 push 동작 설정
git config --global push.default current
```

### 자주 하는 실수와 해결법

| 실수 | 해결 |
|------|------|
| 잘못된 브랜치에 커밋함 | `git reset --soft HEAD~1` → 올바른 브랜치로 이동 → 커밋 |
| 커밋 메시지 오타 | `git commit --amend -m "수정된 메시지"` (push 전에만) |
| 파일을 빼먹고 커밋 | `git add file` → `git commit --amend --no-edit` |
| push 후 되돌리기 | `git revert <commit>` → `git push` |
| 작업 중 급한 다른 작업 | `git stash` → 다른 작업 → `git stash pop` |
| 모든 것이 엉망일 때 | `git reflog`로 이전 상태 찾기 → `git reset` |

### git stash — 작업 임시 저장

```bash
# 현재 작업을 임시 저장 (작업 디렉터리 깨끗해짐)
git stash

# 임시 저장 목록
git stash list
# stash@{0}: WIP on feature/login: abc1234 feat: Add login
# stash@{1}: WIP on main: def5678 Update README

# 임시 저장 복원 (가장 최근)
git stash pop

# 특정 stash 복원
git stash pop stash@{1}

# 임시 저장 삭제
git stash drop stash@{0}

# 모두 삭제
git stash clear
```

```bash
# 실행 예시 — 급한 버그 수정이 필요할 때
$ git stash                          # 현재 작업 임시 저장
Saved working directory and index state WIP on feature/login

$ git checkout main                  # main으로 이동
$ git checkout -b hotfix/urgent-fix  # 핫픽스 브랜치 생성
# ... 버그 수정 ...
$ git commit -am "fix: urgent bug"
$ git checkout feature/login         # 원래 브랜치로 복귀
$ git stash pop                      # 임시 저장한 작업 복원
```

---

> **추가 학습 자료:**
> - [Git 공식 문서](https://git-scm.com/doc) — 모든 명령어의 상세 설명
> - [GitHub Docs](https://docs.github.com) — GitHub 기능 가이드
> - `git help <명령어>` — 터미널에서 바로 도움말 확인
