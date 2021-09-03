#!/bin/bash

TEMP_DIR=/tmp

cp -rf subconverter ${TEMP_DIR}
echo -e "运行规则转换工具"
${TEMP_DIR}/subconverter/subconverter >/dev/null 2>&1 &
