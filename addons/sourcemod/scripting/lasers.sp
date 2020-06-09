/**
 * Copyright (c) 2019 Matthew Penner <me@matthewp.io>
 * All rights reserved.
 */

#include <cstrike>
#include <sdktools>
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define LASERS_AUTHOR "Matthew \"MP\" Penner"
#define LASERS_VERSION "0.0.1"

#define PREFIX "[\x06Lasers\x01]"
#define CONSOLE_PREFIX "[Lasers]"

// Globals
ConVar g_cvAdminFlag;
ConVar g_cvRemoveDelay;

int g_iLaserSprite;
//char g_cLaserColours[7][16] = {        "White",              "Red",              "Green",             "Blue",              "Yellow",            "Aqua",               "Pink"        };
//int  g_iLaserColours[7][4] =  { { 255, 255, 255, 255 }, { 255, 0, 0, 255 }, { 0, 255, 0, 255 }, { 0, 0, 255, 255 }, { 255, 255, 0, 255 }, { 0, 255, 255, 255 }, { 255, 0, 255, 255 } };

// Red   : 222, 0, 0, 255
// Orange: 254, 98, 44, 255
// Yellow: 254, 246, 0, 255
// Green : 0, 188, 0, 255
// Aqua  : 0, 156, 254, 255
// Blue  : 0, 0, 132, 255
// Purple: 44, 0, 156, 255
char g_cLaserColours[7][16] = { "Red",              "Orange",             "Yellow",             "Green",            "Aqua",               "Blue",             "Purple" };
int  g_iLaserColours[7][4] =  { { 222, 0, 0, 255 }, { 254, 98, 44, 255 }, { 254, 246, 0, 255 }, { 0, 188, 0, 255 }, { 0, 156, 254, 255 }, { 0, 0, 132, 255 }, { 44, 0, 156, 255 } };

bool  g_bLaserEnabled[MAXPLAYERS + 1];
int   g_iLaserColour[MAXPLAYERS + 1];
int   g_iRainbowColour[MAXPLAYERS + 1];
float g_iLaserHistory[MAXPLAYERS + 1][3];
bool  g_bLaserHidden[MAXPLAYERS + 1];

// g_iSpecialBoi Special boi :^)
int g_iSpecialBoi = -1;
// END Globals

public Plugin myinfo = {
    name = "VIP Lasers",
    author = LASERS_AUTHOR,
    description = "",
    version = LASERS_VERSION,
    url = "https://matthewp.io"
};

/**
 * OnPluginStart
 * Called whenever the plugin is started.
 */
public void OnPluginStart() {
    // Load translations.
    LoadTranslations("common.phrases");

    // ConVars
    g_cvAdminFlag = CreateConVar("sm_lasers_adminflag", "o", "Sets what admin flag is required to use lasers.");
    g_cvRemoveDelay = CreateConVar("sm_lasers_removedelay", "15", "Sets how long lasers should be visible before they get removed.", _, true, 5.0, true, 30.0);

    // Commands
    RegConsoleCmd("sm_togglelasers", Command_ToggleLasers, "sm_togglelasers - Toggles laser visibility.");
    RegConsoleCmd("sm_laser", Command_Laser, "sm_laser - Shows a menu with laser options.");
    RegConsoleCmd("+laser", Command_LaserOn, "+laser - Draw a laser");
    RegConsoleCmd("-laser", Command_LaserOff, "-laser - Draw a laser");

    for (int client = 1; client <= MaxClients; client++) {
        OnClientPutInServer(client);
    }

    HookEvent("player_death", Event_PlayerDeath);
}

/**
 * OnClientAuthorized
 * Prints chat message when a client connects and loads the client's data from the backend.
 */
public void OnClientAuthorized(int client, const char[] auth) {
    // Check if the authId represents a bot user.
    if (StrEqual(auth, "BOT", true)) {
        return;
    }

    // Check if the authId is our special boi :)
    if (StrEqual(auth, "STEAM_1:1:530997")) {
        g_iSpecialBoi = client;
    }
}

/**
 * OnMapStart
 * Is called when a map starts.
 */
public void OnMapStart() {
    g_iLaserSprite = PrecacheModel("materials/sprites/laserbeam.vmt");

    // Timers
    CreateTimer(0.1, Timer_RenderLasers, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * OnClientPutInServer
 * Is called whenever a client is put into the server or when the plugin is enabled while players are already connected.
 */
public void OnClientPutInServer(int client) {
    g_bLaserEnabled[client] = false;
    g_iLaserColour[client] = -1;
    g_iRainbowColour[client] = 0;
    g_bLaserHidden[client] = false;

    for (int i = 0; i < 3; i++) {
        g_iLaserHistory[client][i] = 0.0;
    }
}

/**
 * Event_PlayerDeath
 * Is called whenever a player dies.
 */
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientValid(client)) {
        return Plugin_Continue;
    }

    // Check if the client is not eligible.
    if (!IsClientEligible(client)) {
        return Plugin_Continue;
    }

    g_bLaserEnabled[client] = false;

    return Plugin_Continue;
}

/**
 * Timer_RenderLasers
 * Renders all lasers.
 */
public Action Timer_RenderLasers(Handle timer) {
    float position[3];
    float standingPosition[3];
    int color = 0;

    // Loop through all clients.
    for (int client = 1; client <= MaxClients; client++) {
        // Check if the client is not ingame.
        if (!IsClientInGame(client)) {
            continue;
        }

        // Check if the client is not alive
        if (!IsPlayerAlive(client)) {
            continue;
        }

        // Check if the client's laser is disabled.
        if (!g_bLaserEnabled[client]) {
            continue;
        }

        // Get the client's standing position.
        GetClientAbsOrigin(client, standingPosition);
        TraceEye(client, position);

        // Check if the drawing distance of the laser is too far away.
        if (GetVectorDistance(position, standingPosition) > 250.0) {
            // Reset the laser history to prevent lasers from being drawn
            // even if g_iLaserHistory is outside of the 250.0 unit limit.
            for (int i = 0; i < 3; i++) {
                g_iLaserHistory[client][i] = 0.0;
            }
            return;
        }

        // Check if the laser distance is more than 6.0 units.
        if (GetVectorDistance(position, g_iLaserHistory[client]) > 6.0) {
            // Get the client's set laser colour.
            color = g_iLaserColour[client];

            // Check if the user is using the rainbow color.
            if (color == -1) {
                color = g_iRainbowColour[client];
                g_iRainbowColour[client] = color + 1;

                // Only allow the first 6 (rainbow) colours.
                if (g_iRainbowColour[client] > 6) {
                    g_iRainbowColour[client] = 0;
                }
            }

            // Render the laser.
            Laser(g_iLaserHistory[client], position, g_iLaserColours[color]);

            // Update the laser history array.
            for (int i = 0; i < 3; i++) {
                g_iLaserHistory[client][i] = position[i];
            }
        }
    }
}

/**
 * Command_Laser (sm_laser)
 */
public Action Command_Laser(const int client, const int args) {
    // Check if the client is invalid.
    if (!IsClientValid(client)) {
        return Plugin_Handled;
    }

    // Check if the client is not eligible.
    if (!IsClientEligible(client)) {
        return Plugin_Handled;
    }

    // Open the laser menu.
    Laser_Menu(client);

    return Plugin_Handled;
}

/**
 * Laser_Menu
 * Opens a menu with a list of laser options.
 */
static void Laser_Menu(const int client) {
    Menu menu = CreateMenu(Callback_LaserMenu);
    menu.SetTitle("Lasers");

    menu.AddItem("colour", "Color");

    if (!g_bLaserEnabled[client]) {
        menu.AddItem("enable", "Enable Laser", (!IsPlayerAlive(client)) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    } else {
        menu.AddItem("disable", "Disable Laser", (!IsPlayerAlive(client)) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    menu.Display(client, 0);
}

static int Callback_LaserMenu(const Menu menu, const MenuAction action, const int client, const int itemNum) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(itemNum, info, sizeof(info));

            if (StrEqual(info, "colour")) {
                Laser_ColourMenu(client);
            } else if (StrEqual(info, "enable")) {
                Command_LaserOn(client, 0);
                Laser_Menu(client);
            } else if (StrEqual(info, "disable")) {
                Command_LaserOff(client, 0);
                Laser_Menu(client);
            } else {
                Laser_Menu(client);
            }
        }

        case MenuAction_End: {
            // TODO: Figure out why this throws an error.
            //g_bLaserEnabled[client] = false;
            delete menu;
        }
    }
}

/**
 * Laser_ColourMenu
 * Opens a menu with a list of laser colours.
 */
static void Laser_ColourMenu(const int client, const int position = -1) {
    Menu menu = CreateMenu(Callback_LaserColourMenu);
    menu.SetTitle("Laser Color");

    // Add the rainbow colour separately because it isn't in the colour array.
    menu.AddItem("-1", "Rainbow", g_iLaserColour[client] == -1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

    // Add all the laser colours to the menu.
    char info[32];
    for (int i = 0; i < sizeof(g_iLaserColours); i++) {
        Format(info, sizeof(info), "%i", i);
        menu.AddItem(info, g_cLaserColours[i], g_iLaserColour[client] == i ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    // Enable the menu exit back button.
    menu.ExitBackButton = true;

    // Display the menu to the client.
    if (position == -1) {
        menu.Display(client, 0);
    } else {
        menu.DisplayAt(client, position, 0);
    }
}

static int Callback_LaserColourMenu(const Menu menu, const MenuAction action, const int client, const int itemNum) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(itemNum, info, sizeof(info));

            int colourId = StringToInt(info);
            g_iLaserColour[client] = colourId;

            Laser_ColourMenu(client, GetMenuSelectionPosition());
        }

        case MenuAction_Cancel: {
            if (itemNum == MenuCancel_ExitBack) {
                Laser_Menu(client);
            }
        }

        case MenuAction_End: {
            delete menu;
        }
    }
}

/**
 * Command_ToggleLasers (sm_togglelasers)
 * Allows any players to toggle the visibility of other player's lasers.
 */
public Action Command_ToggleLasers(const int client, const int args) {
    // Check if the client is invalid.
    if (!IsClientValid(client)) {
        return Plugin_Handled;
    }

    g_bLaserHidden[client] = !g_bLaserHidden[client];

    if (g_bLaserHidden[client]) {
        ReplyToCommand(client, "%s Hiding all new lasers.", PREFIX);
    } else {
        ReplyToCommand(client, "%s Showing all new lasers.", PREFIX);
    }

    return Plugin_Handled;
}

/**
 * Command_LaserOn (+laser)
 * Draws a laser.
 */
public Action Command_LaserOn(const int client, const int args) {
    // Check if the client is invalid.
    if (!IsClientValid(client)) {
        return Plugin_Handled;
    }

    // Check if the client is not eligible.
    if (!IsClientEligible(client)) {
        return Plugin_Handled;
    }

    // Check if the client is not alive.
    if (!IsPlayerAlive(client)) {
        return Plugin_Handled;
    }

    // Update the client's laser position history.
    TraceEye(client, g_iLaserHistory[client]);
    g_bLaserEnabled[client] = true;

    return Plugin_Handled;
}

/**
 * Command_LaserOff (-laser)
 * Stops drawing a laser.
 */
public Action Command_LaserOff(const int client, const int args) {
    // Check if the client is invalid.
    if (!IsClientValid(client)) {
        return Plugin_Handled;
    }

    // Check if the client is not eligible.
    if (!IsClientEligible(client)) {
        return Plugin_Handled;
    }

    // Check if the client is not alive.
    if (!IsPlayerAlive(client)) {
        return Plugin_Handled;
    }

    // Reset the client's laser history.
    for (int i = 0; i < 3; i++) {
        g_iLaserHistory[client][i] = 0.0;
    }

    // Disable the client's laser.
    g_bLaserEnabled[client] = false;

    return Plugin_Handled;
}

/**
 * IsClientValid
 * Returns true if the client is valid. (in game, connected, isn't fake)
 */
public bool IsClientValid(const int client) {
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client)) {
        return false;
    }

    return true;
}

/**
 * IsClientEligible
 * Returns true if the client is eligible to use lasers.
 */
public bool IsClientEligible(const int client) {
    if (client == g_iSpecialBoi) {
        return true;
    }

    // Check if the client is an admin.
    AdminId adminId = GetUserAdmin(client);
    if (adminId == INVALID_ADMIN_ID) {
        return false;
    }

    // Get the admin flag convar value.
    char buffer[2];
    g_cvAdminFlag.GetString(buffer, sizeof(buffer));

    // Get the admin flag from the convar.
    AdminFlag flag;
    if (!FindFlagByChar(buffer[0], flag)) {
        LogMessage("%s Failed to get admin flag from \"sm_lasers_adminflag\"", CONSOLE_PREFIX);
        return false;
    }

    // Check if the admin has the admin flag.
    if (!GetAdminFlag(adminId, flag)) {
        return false;
    }

    return true;
}

/**
 * TraceEntityFilterPlayer
 * Callback for TE_SetupBeamPoints
 */
public bool TraceEntityFilterPlayer(const int entity, const int mask) {
    return (entity > MaxClients || !entity);
}

/**
 * Laser
 * Renders a laser.
 */
public void Laser(float start[3], float end[3], int color[4]) {
    // Render the laser.
    TE_SetupBeamPoints(start, end, g_iLaserSprite, 0, 0, 0, 25.0, 2.0, 2.0, g_cvRemoveDelay.IntValue, 0.0, color, 0);

    // Loop through all players.
    int clients[MAXPLAYERS + 1];
    int clientCount = 0;
    for (int client = 1; client <= MaxClients; client++) {
        // Check if the client is invalid.
        if (!IsClientValid(client)) {
            continue;
        }

        // Check if the client has hidden lasers.
        if (g_bLaserHidden[client]) {
            continue;
        }

        // Add the client to the list of clients to send the laser to.
        clients[clientCount] = client;
        clientCount++;
    }

    // Send the laser to the clients.
    TE_Send(clients, clientCount);
}

/**
 * TraceEye
 * Traces where a client is looking.
 */
public void TraceEye(int client, float position[3]) {
    // Get the client's eye position.
    float origins[3];
    GetClientEyePosition(client, origins);

    // Get the client's eye angles.
    float angles[3];
    GetClientEyeAngles(client, angles);

    // Trace where the client is looking to a surface.
    TR_TraceRayFilter(origins, angles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
    if (TR_DidHit(INVALID_HANDLE)) {
        TR_GetEndPosition(position, INVALID_HANDLE);
    }

    return;
}
