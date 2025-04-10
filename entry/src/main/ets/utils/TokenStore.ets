import { KvManager } from "./KvManager";
import { TokenConfig } from "./TokenConfig";
import { RdbManager } from "./RdbManager";
import { common } from '@kit.AbilityKit';

export class TokenStore {
  private kvMgr: KvManager = KvManager.getInstance();
  private rdbMgr: RdbManager = RdbManager.getInstance();
  private token_array: TokenConfig[] = [];
  private appCtx: common.UIAbilityContext | undefined = undefined;
  private init_done: boolean = false;
  private static instance: TokenStore;

  private token_prefix: string = "_token_uuid_";

  private constructor() {
  }

  private async emitTokenChanged(): Promise<void> {
    this.appCtx?.eventHub.emit('onTokenChanged');
  }

  public static getInstance(): TokenStore {
    if (!TokenStore.instance) {
      TokenStore.instance = new TokenStore();
    }
    return TokenStore.instance;
  }

  public async initTokenStore(): Promise<void> {
    if (this.init_done) {
      return;
    }
    await this.kvMgr.initKvManager();
    await this.LoadTokenByDataBase();
    this.init_done = true;
  }

  public async LoadTokenByDataBase(): Promise<void> {
     this.token_array = await this.kvMgr.getTokenArray(this.token_prefix)
     this.appCtx = AppStorage.get<common.UIAbilityContext>('appContext') as common.UIAbilityContext;
     this.sortTokens();
  }

  public async getTokens(): Promise<TokenConfig[]> {
    return this.token_array;
  }

  public async queryToken(token_uuid: string): Promise<TokenConfig> {
    let token = await this.kvMgr.getValue<TokenConfig>(`${this.token_prefix}${token_uuid}`);
    return token ?? new TokenConfig();
  }

  public sortTokens(): void {
    this.token_array = this.token_array.sort((a, b) => a.RankScore - b.RankScore)
    this.emitTokenChanged();
  }

  private async saveToken(token: TokenConfig): Promise<void> {
    await this.kvMgr.setValue<TokenConfig>(`${this.token_prefix}${token.TokenUUID}`, token);
  }

  public async updateTokenRank(from: number, to: number): Promise<void> {
    this.token_array[from].RankScore = to;
    await this.saveToken(this.token_array[from]);
    if (from > to) {
      for (let i = to; i < from; i++) {
        this.token_array[i].RankScore++;
        await this.saveToken(this.token_array[i]);
      }
    } else {
      for (let i = from + 1; i <= to; i++) {
        this.token_array[i].RankScore--;
        await this.saveToken(this.token_array[i]);
      }
    }
    this.sortTokens();
  }

  public async updateToken(token: TokenConfig): Promise<void> {
    let token_new = token;
    const token_uuids = this.token_array.map(t => t.TokenUUID);
    if (!token_uuids.includes(token_new.TokenUUID)) {
      token_new.RankScore = this.token_array.length;
      this.token_array.push(token_new);
    } else {
      const token_index = token_uuids.findIndex(uuid => uuid === token_new.TokenUUID);
      token_new.RankScore = this.token_array[token_index].RankScore;
      this.token_array[token_index] = token_new;
    }
    await this.saveToken(token_new);
    this.emitTokenChanged();
  }

  public async deleteToken(token_uuid: string): Promise<void> {
    const token_uuids = this.token_array.map(t => t.TokenUUID);
    const token_index = token_uuids.findIndex(uuid => uuid === token_uuid);
    for (let i = token_index; i < this.token_array.length; i++) {
      this.token_array[i].RankScore--;
      await this.saveToken(this.token_array[i]);
    }
    this.token_array = this.token_array.filter(t => t.TokenUUID !== token_uuid);
    await this.kvMgr.deleteValue(`${this.token_prefix}${token_uuid}`);
    this.emitTokenChanged();
  }

  //手动同步
  async DataSync(): Promise<void> {
    await this.kvMgr.DataSync();
  }
}