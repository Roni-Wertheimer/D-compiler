import std.stdio;
import std.string;
import std.path;
import std.file;
import std.array;

// ==========================================
// משתנים גלובאליים (הכרחי כדי לאפשר פונקציות ללא פרמטרים)
// ==========================================
string currentFileName; // דרישה סעיף 2.e.ii
File outFile;           // קובץ הפלט שאליו כולם כותבים
int logicCounter;       // מונה פקודות לוגיות

void main() {
    // קבלת נתיב מהמשתמש
    write("Please enter the directory path: ");
    string dirPath = readln().strip();

    if (!exists(dirPath) || !isDir(dirPath)) {
        writeln("Error: Directory not found.");
        return;
    }

    // חילוץ שם התיקייה ויצירת קובץ הפלט
    string dirName = baseName(dirPath);
    string outFilePath = buildPath(dirPath, dirName ~ ".asm");
    
    // פתיחת קובץ הפלט לכתיבה (נשמר במשתנה הגלובאלי)
    outFile = File(outFilePath, "w");

    // מעבר על כל קבצי ה-VM בתיקייה
    foreach (string entry; dirEntries(dirPath, "*.vm", SpanMode.shallow)) {
        
        // שמירת שם הקובץ ללא סיומת
        currentFileName = baseName(entry, ".vm");
        
        // איפוס המונה עבור כל קובץ מחדש
        logicCounter = 1; 

        // פתיחת הקובץ הנוכחי לקריאה
        File inFile = File(entry, "r");

        // קריאת הקובץ שורה אחר שורה
        foreach (line; inFile.byLine()) {
            auto words = line.idup.split(); 
            if (words.length == 0) continue; 

            string command = words[0];

            // זימון פונקציות העזר
            switch(command) {
                case "add": handleAdd(); break;
                case "sub": handleSub(); break;
                case "neg": handleNeg(); break;
                
                case "eq": handleEq(); break;
                case "gt": handleGt(); break;
                case "lt": handleLt(); break;
                
                case "push": 
                    if (words.length >= 3) handlePush(words[1], words[2]); 
                    break;
                case "pop": 
                    if (words.length >= 3) handlePop(words[1], words[2]); 
                    break;
                default: break;
            }
        }

        inFile.close();
        writeln("End of input file: ", baseName(entry));
    }

    outFile.close();
    writeln("Output file is ready: ", dirName, ".asm");
}

// ==========================================
// פונקציות עזר (מדויקות לפי הטבלה)
// ==========================================

// פקודות אריתמטיות - ללא פרמטרים כלל
void handleAdd() { outFile.writeln("command: add"); }
void handleSub() { outFile.writeln("command: sub"); }
void handleNeg() { outFile.writeln("command: neg"); }

// פקודות לוגיות - ללא פרמטרים כלל. מקדמות את המונה לאחר השימוש.
void handleEq()  { 
    outFile.writeln("command: eq"); 
    outFile.writeln("counter: ", logicCounter++); 
}
void handleGt()  { 
    outFile.writeln("command: gt"); 
    outFile.writeln("counter: ", logicCounter++); 
}
void handleLt()  { 
    outFile.writeln("command: lt"); 
    outFile.writeln("counter: ", logicCounter++); 
}

// פקודות גישה לזיכרון - מקבלות 2 פרמטרים בדיוק
void handlePush(string segment, string index) {
    outFile.writeln("command: push segment ", segment, " index ", index);
}
void handlePop(string segment, string index) {
    outFile.writeln("command: pop segment ", segment, " index ", index);
}