import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CashService } from './cash.service';
import { CreateCashEntryDto, UpdateCashEntryDto } from './dto/create-cash-entry.dto';
import { QueryCashDto, QueryCashSummaryDto } from './dto/query-cash.dto';

@ApiTags('cash')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('cash')
export class CashController {
  constructor(private readonly cash: CashService) {}

  /** 201 a la creation, 200 si un envoi rejoue (meme `id`) renvoie l'ecriture existante. */
  @Post()
  async create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateCashEntryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { entry, created } = await this.cash.create(user.id, dto);
    if (!created) res.status(HttpStatus.OK);
    return entry;
  }

  @Get()
  list(@CurrentUser() user: AuthenticatedUser, @Query() query: QueryCashDto) {
    return this.cash.list(user.id, query);
  }

  @Get('summary')
  summary(@CurrentUser() user: AuthenticatedUser, @Query() query: QueryCashSummaryDto) {
    const from = new Date(query.from);
    const to = new Date(query.to);
    if (!(from < to)) throw new BadRequestException('La periode est invalide : "from" doit preceder "to"');
    return this.cash.summary(user.id, from, to);
  }

  @Patch(':id')
  update(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string, @Body() dto: UpdateCashEntryDto) {
    return this.cash.update(user.id, id, dto);
  }

  @Delete(':id')
  remove(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.cash.remove(user.id, id);
  }
}
