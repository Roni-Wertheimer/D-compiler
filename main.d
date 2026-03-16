/*
 Aharon wertheimer 206447773
 Moshe shushan 316314731
*/

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.array;

// Global variables 
string currentFileName; 
File outFile;           // The file we write to
int logicCounter;       // Counter for logic commands

void main() {
    // Ask user for the folder path
    write("Please enter the directory path: ");
    string dirPath = readln().strip(); // Read input and clean it

    // Check if the folder exists
    if (!exists(dirPath) || !isDir(dirPath)) {
        writeln("Error: Directory not found.");
        return;
    }

    // Create the output file name
    string dirName = baseName(dirPath); // Get the folder name
    string outFilePath = buildPath(dirPath, dirName ~ ".asm"); // Add .asm extension
    outFile = File(outFilePath, "w"); // Open file to write

    // Go through all .vm files in the folder
    foreach (string entry; dirEntries(dirPath, "*.vm", SpanMode.shallow)) {
        currentFileName = baseName(entry, ".vm"); // Get name without .vm
        logicCounter = 1; // Start counter at 1 for each file
        
        File inFile = File(entry, "r"); // Open VM file to read

        // Read the file line by line
        foreach (line; inFile.byLine()) {
            auto words = line.idup.split(); // Break line into words
            if (words.length == 0) continue; // Skip if line is empty

            string command = words[0]; // The first word is the command
            
            // Check which command it is
            switch(command) {
                case "add": handleAdd(); break;
                case "sub": handleSub(); break;
                case "neg": handleNeg(); break;
                case "eq":  handleEq();  break;
                case "gt":  handleGt();  break;
                case "lt":  handleLt();  break;
                case "push": 
                    if (words.length >= 3) handlePush(words[1], words[2]); 
                    break;
                case "pop":  
                    if (words.length >= 3) handlePop(words[1], words[2]); 
                    break;
                default: break; // Do nothing for other words
            }
        }

        inFile.close(); // Finished reading this file
        writeln("End of input file: ", baseName(entry));
    }

    outFile.close(); // Finished writing the output file
    writeln("Output file is ready: ", dirName, ".asm");
}

// Functions to write simple commands
void handleAdd() { outFile.writeln("command: add"); }
void handleSub() { outFile.writeln("command: sub"); }
void handleNeg() { outFile.writeln("command: neg"); }

// Functions for logic commands (they use the counter)
void handleEq()  { 
    outFile.writeln("command: eq"); 
    outFile.writeln("counter: ", logicCounter++); // Print then add 1
}
void handleGt()  { 
    outFile.writeln("command: gt"); 
    outFile.writeln("counter: ", logicCounter++); 
}
void handleLt()  { 
    outFile.writeln("command: lt"); 
    outFile.writeln("counter: ", logicCounter++); 
}

// Functions for memory commands (push/pop)
void handlePush(string segment, string index) {
    outFile.writeln("command: push segment ", segment, " index ", index);
}
void handlePop(string segment, string index) {
    outFile.writeln("command: pop segment ", segment, " index ", index);
}