# 공통 Python 함수

원본 user_functions.ipynb의 공통 기능을 [user_functions.py](user_functions.py) 모듈로 옮겼습니다. 각 실습은 이 모듈을 직접 import하므로 노트북 가져오기 플러그인이나 OML4Py가 필요하지 않습니다.

## 함수별 역할

| 함수 | 역할 |
| --- | --- |
| get_conn_cursor | DB 연결과 커서를 생성합니다. |
| get_db_version | DB 제품·버전을 DataFrame으로 반환합니다. |
| exec_sql | 조회 결과의 LOB 값을 읽어 DataFrame으로 반환합니다. |
| exec_sql_rows | 원시 행 목록을 반환합니다. LOB은 연결이 열려 있을 때 읽습니다. |
| dml_sql | DML 성공 시 커밋하고, 실패하면 롤백한 뒤 오류를 전달합니다. |
| ddl_sql | DDL을 실행합니다. Oracle의 DDL은 암묵적 커밋을 유발할 수 있습니다. |
| read_lob | 드라이버 LOB을 읽고 일반 문자열·숫자·벡터는 그대로 반환합니다. |
| clean_text / clean_text1 / clean_text2 | 제어문자와 표시 공백을 정리합니다. 의미 있는 문장부호·법령 조항·수치는 제거하지 않습니다. |
| display / img_show | 표·이미지를 표시합니다. Jupyter가 없으면 표는 텍스트로 출력합니다. |

원본의 정의되지 않은 clean_text 참조를 보완하고, 문자열 정리 함수에 DataFrame을 전달해도 동작하도록 정리했습니다. 이 함수들은 임베딩 모델의 전처리를 대신하지 않습니다.

## 실행 모듈 전체 코드

아래 코드는 user_functions.py와 동일합니다. 같은 코드를 두 번 입력할 필요 없이 파일을 import합니다.

```python
"""Shared helpers for the similarity_search Markdown labs."""

import re

import oracledb
import pandas as pd


def display(value):
    """Render in a notebook, or print the underlying table in a Python shell."""
    try:
        from IPython import get_ipython
        from IPython.display import display as ipython_display
        if get_ipython() is not None:
            ipython_display(value)
            return
    except ImportError:
        pass
    print(getattr(value, "data", value))


def get_conn_cursor(user, password, dsn):
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    try:
        return conn, conn.cursor()
    except Exception:
        conn.close()
        raise


def read_lob(value):
    """Read a driver LOB while its connection is still open; preserve scalars."""
    return value.read() if isinstance(value, oracledb.LOB) else value


def get_db_version(cursor):
    return exec_sql(cursor, "SELECT product, version_full FROM product_component_version")


def exec_sql_rows(cursor, qry, bind_var=None):
    """Return raw rows. Read any LOB locators before closing the connection."""
    cursor.execute(qry, bind_var if bind_var is not None else {})
    return cursor.fetchall()


def exec_sql(cursor, qry, bind_var=None):
    """Return a DataFrame, materializing LOB values before another cursor call."""
    rows = exec_sql_rows(cursor, qry, bind_var)
    cols = [col[0] for col in cursor.description]
    values = [tuple(read_lob(value) for value in row) for row in rows]
    return pd.DataFrame(values, columns=cols)


def dml_sql(conn, cursor, sql, bind_var=None):
    """Execute DML and commit on success; roll back and propagate failures."""
    try:
        cursor.execute(sql, bind_var if bind_var is not None else {})
        affected = cursor.rowcount
        conn.commit()
        return affected
    except Exception:
        conn.rollback()
        raise


def ddl_sql(cursor, sql):
    """Execute DDL. Oracle DDL can implicitly commit the transaction."""
    cursor.execute(sql)


def clean_text2(value):
    """Normalize display whitespace while preserving meaningful punctuation."""
    value = read_lob(value)
    if value is None:
        return ""
    if not isinstance(value, str):
        return value
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", value)
    value = re.sub(r"[ \t]+", " ", value)
    return re.sub(r"\n{3,}", "\n\n", value).strip()


def clean_text(value):
    if isinstance(value, pd.DataFrame):
        result = value.copy()
        for name in result.columns:
            result[name] = result[name].map(
                lambda cell: clean_text2(cell) if isinstance(cell, str) else cell
            )
        return result
    return clean_text2(value)


def clean_text1(value):
    """Compatibility alias used by the original lab cells."""
    return clean_text(value)


def img_show(img):
    from PIL import Image
    import matplotlib.pyplot as plt
    with Image.open(img) as source:
        plt.figure(figsize=(5, 4))
        plt.imshow(source)
        plt.axis("off")
        plt.show()
```

DB 접속 정보를 코드에 고정하지 않고 환경 변수 또는 getpass 입력을 사용합니다. 조회 결과의 LOB을 연결 종료 후 읽으면 실패할 수 있으므로 먼저 읽은 뒤 연결을 닫습니다.

[전체 실습 안내](readme.md)
