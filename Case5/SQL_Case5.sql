-- -----------------------------------------
-- Проект: Система онлайн-обучения
-- СУБД: MariaDB 10.3+ / 12.0
-- Ошибки: Исправлены синтаксические (ERROR 1064)
-- -----------------------------------------

-- Удаляем старую базу
DROP DATABASE IF EXISTS elearning_db;
CREATE DATABASE elearning_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE elearning_db;

-- Отключаем проверку внешних ключей
SET FOREIGN_KEY_CHECKS = 0;

-- Удаляем таблицы в обратном порядке
DROP TABLE IF EXISTS certificates;
DROP TABLE IF EXISTS lesson_progress;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS quiz_questions;
DROP TABLE IF EXISTS quizzes;
DROP TABLE IF EXISTS lessons;
DROP TABLE IF EXISTS modules;
DROP TABLE IF EXISTS enrollments;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS users;

-- Включаем проверку
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------
-- 1. Пользователи
-- -----------------------------------------
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    role ENUM('student', 'instructor', 'admin') DEFAULT 'student',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    metadata JSON,
    INDEX idx_email (email),
    INDEX idx_role (role)
) ENGINE=InnoDB;

-- -----------------------------------------
-- 2. Курсы
-- -----------------------------------------
CREATE TABLE courses (
    course_id INT PRIMARY KEY AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    level ENUM('beginner', 'intermediate', 'advanced'),
    instructor_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_published BOOLEAN DEFAULT FALSE,
    duration_hours DECIMAL(5,2),
    FOREIGN KEY (instructor_id) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_courses_instructor ON courses(instructor_id);
CREATE INDEX idx_courses_published ON courses(is_published);
CREATE INDEX idx_courses_level ON courses(level);

-- -----------------------------------------
-- 3. Модули
-- -----------------------------------------
CREATE TABLE modules (
    module_id INT PRIMARY KEY AUTO_INCREMENT,
    course_id INT NOT NULL,
    title VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 0,
    FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------
-- 4. Уроки
-- -----------------------------------------
CREATE TABLE lessons (
    lesson_id INT PRIMARY KEY AUTO_INCREMENT,
    module_id INT NOT NULL,
    title VARCHAR(100) NOT NULL,
    content TEXT,
    video_url VARCHAR(255),
    duration_minutes INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (module_id) REFERENCES modules(module_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_lessons_module ON lessons(module_id);

-- -----------------------------------------
-- 5. Тесты
-- -----------------------------------------
CREATE TABLE quizzes (
    quiz_id INT PRIMARY KEY AUTO_INCREMENT,
    lesson_id INT UNIQUE,
    passing_score INT DEFAULT 70,
    time_limit_minutes INT,
    FOREIGN KEY (lesson_id) REFERENCES lessons(lesson_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------
-- 6. Вопросы тестов
-- -----------------------------------------
CREATE TABLE quiz_questions (
    question_id INT PRIMARY KEY AUTO_INCREMENT,
    quiz_id INT NOT NULL,
    question_text TEXT NOT NULL,
    options JSON,
    correct_answer VARCHAR(255),
    FOREIGN KEY (quiz_id) REFERENCES quizzes(quiz_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------
-- 7. Запись на курс
-- -----------------------------------------
CREATE TABLE enrollments (
    enrollment_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    course_id INT NOT NULL,
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE KEY uk_user_course (user_id, course_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_enrollments_user ON enrollments(user_id);
CREATE INDEX idx_enrollments_course ON enrollments(course_id);

-- -----------------------------------------
-- 8. Прогресс по урокам
-- -----------------------------------------
CREATE TABLE lesson_progress (
    progress_id INT PRIMARY KEY AUTO_INCREMENT,
    enrollment_id INT NOT NULL,
    lesson_id INT NOT NULL,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMP NULL,
    time_spent_seconds INT DEFAULT 0,
    UNIQUE KEY uk_enr_lesson (enrollment_id, lesson_id),
    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (lesson_id) REFERENCES lessons(lesson_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_progress_enrollment ON lesson_progress(enrollment_id);
CREATE INDEX idx_progress_completed ON lesson_progress(is_completed);

-- -----------------------------------------
-- 9. Сертификаты
-- -----------------------------------------
CREATE TABLE certificates (
    certificate_id INT PRIMARY KEY AUTO_INCREMENT,
    enrollment_id INT UNIQUE,
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    certificate_url VARCHAR(255) NOT NULL,
    hash_sha256 CHAR(64),
    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- -----------------------------------------
-- 10. Комментарии
-- -----------------------------------------
CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    lesson_id INT NOT NULL,
    parent_comment_id INT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_edited BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (lesson_id) REFERENCES lessons(lesson_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_comments_lesson ON comments(lesson_id);
CREATE INDEX idx_comments_user ON comments(user_id);

-- -----------------------------------------
-- Представление: Активные курсы
-- -----------------------------------------
CREATE OR REPLACE VIEW active_courses AS
SELECT 
    c.course_id,
    c.title,
    c.level,
    CONCAT(u.first_name, ' ', u.last_name) AS instructor_name,
    COUNT(e.enrollment_id) AS student_count,
    c.duration_hours
FROM courses c
JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN enrollments e ON c.course_id = e.course_id
WHERE c.is_published = TRUE
GROUP BY c.course_id, u.user_id, u.first_name, u.last_name;

-- -----------------------------------------
-- Триггер 1: Выдача сертификата при INSERT в lesson_progress
-- -----------------------------------------
DELIMITER $$

DROP TRIGGER IF EXISTS trg_issue_certificate;

CREATE TRIGGER trg_issue_certificate
AFTER INSERT ON lesson_progress
FOR EACH ROW
BEGIN
    DECLARE total_lessons INT DEFAULT 0;
    DECLARE completed_lessons INT DEFAULT 0;
    DECLARE course_id_val INT DEFAULT 0;

    -- Проверяем, завершён ли урок
    IF NEW.is_completed = TRUE THEN
        -- Начало блока операций
        BEGIN
            -- Получаем ID курса
            SELECT c.course_id INTO course_id_val
            FROM enrollments e
            JOIN courses c ON e.course_id = c.course_id
            WHERE e.enrollment_id = NEW.enrollment_id
            LIMIT 1;

            -- Общее количество уроков в курсе
            SELECT COUNT(*) INTO total_lessons
            FROM lessons l
            JOIN modules m ON l.module_id = m.module_id
            WHERE m.course_id = course_id_val;

            -- Количество завершённых уроков
            SELECT COUNT(*) INTO completed_lessons
            FROM lesson_progress lp
            JOIN lessons l ON lp.lesson_id = l.lesson_id
            JOIN modules m ON l.module_id = m.module_id
            WHERE lp.enrollment_id = NEW.enrollment_id
              AND lp.is_completed = TRUE
              AND m.course_id = course_id_val;

            -- Если все уроки завершены и сертификата нет — выдаём
            IF completed_lessons = total_lessons THEN
                IF NOT EXISTS (SELECT 1 FROM certificates WHERE enrollment_id = NEW.enrollment_id) THEN
                    INSERT INTO certificates (enrollment_id, certificate_url, hash_sha256)
                    VALUES (
                        NEW.enrollment_id,
                        CONCAT('https://elearning.example.com/cert/', NEW.enrollment_id),
                        SHA2(CONCAT(NEW.enrollment_id, NOW()), 256)
                    );
                END IF;
            END IF;
        END; -- конец блока BEGIN
    END IF; -- конец IF
END$$

-- -----------------------------------------
-- Триггер 2: Выдача сертификата при UPDATE (на случай редактирования)
-- -----------------------------------------
DROP TRIGGER IF EXISTS trg_issue_certificate_update;

CREATE TRIGGER trg_issue_certificate_update
AFTER UPDATE ON lesson_progress
FOR EACH ROW
BEGIN
    DECLARE total_lessons INT DEFAULT 0;
    DECLARE completed_lessons INT DEFAULT 0;
    DECLARE course_id_val INT DEFAULT 0;

    IF NEW.is_completed = TRUE THEN
        BEGIN
            SELECT c.course_id INTO course_id_val
            FROM enrollments e
            JOIN courses c ON e.course_id = c.course_id
            WHERE e.enrollment_id = NEW.enrollment_id
            LIMIT 1;

            SELECT COUNT(*) INTO total_lessons
            FROM lessons l
            JOIN modules m ON l.module_id = m.module_id
            WHERE m.course_id = course_id_val;

            SELECT COUNT(*) INTO completed_lessons
            FROM lesson_progress lp
            JOIN lessons l ON lp.lesson_id = l.lesson_id
            JOIN modules m ON l.module_id = m.module_id
            WHERE lp.enrollment_id = NEW.enrollment_id
              AND lp.is_completed = TRUE
              AND m.course_id = course_id_val;

            IF completed_lessons = total_lessons THEN
                IF NOT EXISTS (SELECT 1 FROM certificates WHERE enrollment_id = NEW.enrollment_id) THEN
                    INSERT INTO certificates (enrollment_id, certificate_url, hash_sha256)
                    VALUES (
                        NEW.enrollment_id,
                        CONCAT('https://elearning.example.com/cert/', NEW.enrollment_id),
                        SHA2(CONCAT(NEW.enrollment_id, NOW()), 256)
                    );
                END IF;
            END IF;
        END;
    END IF;
END$$

DELIMITER ;

-- -----------------------------------------
-- Тестовые данные
-- -----------------------------------------
INSERT INTO users (email, password_hash, first_name, last_name, role) VALUES
('anna@edu.com', 'hash123', 'Анна', 'Петрова', 'student'),
('ivan@edu.com', 'hash456', 'Иван', 'Сидоров', 'instructor');

INSERT INTO courses (title, description, level, instructor_id, is_published, duration_hours)
VALUES ('Python для начинающих', 'Введение в Python', 'beginner', 2, TRUE, 10.5);

INSERT INTO modules (course_id, title) VALUES (1, 'Основы');
INSERT INTO lessons (module_id, title) VALUES (1, 'Переменные');
INSERT INTO enrollments (user_id, course_id) VALUES (1, 1);

-- Этот INSERT должен запустить триггер и создать сертификат
INSERT INTO lesson_progress (enrollment_id, lesson_id, is_completed, completed_at)
VALUES (1, 1, TRUE, NOW());

-- Проверка:
SELECT * FROM certificates;
SELECT * FROM active_courses;