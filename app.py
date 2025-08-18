from flask import Flask, request, render_template, redirect, url_for
import psycopg2
import boto3
import os

app = Flask(__name__)

# Configuración RDS
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASS = os.environ.get('DB_PASS')

# Configuración S3
S3_BUCKET = os.environ.get('S3_BUCKET')

def get_db_conn():
    return psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASS)

s3 = boto3.client('s3')

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        nombre = request.form['nombre']
        archivo = request.files['archivo']
        if archivo:
            s3.upload_fileobj(archivo, S3_BUCKET, archivo.filename)
            # Guardar info en RDS
            conn = get_db_conn()
            cur = conn.cursor()
            cur.execute("INSERT INTO usuarios (nombre, archivo) VALUES (%s, %s)", (nombre, archivo.filename))
            conn.commit()
            cur.close()
            conn.close()
            return "¡Guardado!"
    return '''
        <form method="post" enctype="multipart/form-data">
            Nombre: <input name="nombre"><br>
            Archivo: <input type="file" name="archivo"><br>
            <button type="submit">Subir</button>
        </form>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)